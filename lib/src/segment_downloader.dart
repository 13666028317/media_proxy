// =============================================================================
// SegmentDownloader - 分片下载器（优化版）
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'config.dart';
import 'enums.dart';
import 'media_segment.dart';
import 'utils.dart';

/// 分片下载器
///
/// 负责下载单个分片，支持断点续传和重试机制
class SegmentDownloader {
  /// 下载分片（带重试机制）
  static Future<bool> downloadSegment({
    required String mediaUrl,
    required MediaSegment segment,
    required Directory cacheDir,
    Map<String, String>? headers,
    void Function(int downloadedBytes)? onProgress,
    bool Function()? cancelToken,
  }) async {
    int retryCount = 0;
    int delay = MediaProxyConfig.instance.downloadRetryInitialDelayMs;

    while (retryCount < MediaProxyConfig.instance.downloadRetryCount) {
      try {
        final result = await _downloadSegmentInternal(
          mediaUrl: mediaUrl,
          segment: segment,
          cacheDir: cacheDir,
          headers: headers,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        if (result) return true;
      } catch (e) {
        log(
          () =>
              'Download attempt ${retryCount + 1}/${MediaProxyConfig.instance.downloadRetryCount} failed: $e',
        );
      }

      retryCount++;
      if (retryCount < MediaProxyConfig.instance.downloadRetryCount) {
        await Future.delayed(Duration(milliseconds: delay));
        delay *= 2;
      }
    }

    return false;
  }

  /// 内部下载逻辑
  static Future<bool> _downloadSegmentInternal({
    required String mediaUrl,
    required MediaSegment segment,
    required Directory cacheDir,
    Map<String, String>? headers,
    void Function(int downloadedBytes)? onProgress,
    bool Function()? cancelToken,
  }) async {
    final tempFile = segment.getTempFile(cacheDir);
    final finalFile = segment.getSegmentFile(cacheDir);

    // 🔑 防止并发下载：如果分片已经完成，直接返回
    if (segment.isCompleted) {
      log(() => 'Segment already marked completed, skipping: $segment');
      return true;
    }

    // 检查是否已下载完成（通过文件验证）
    if (await finalFile.exists()) {
      final fileSize = await finalFile.length();
      if (fileSize >= segment.expectedSize) {
        segment.downloadedBytes = fileSize;
        segment.updateStatus(SegmentStatus.completed);
        log(() => 'Segment already completed: $segment');
        return true;
      }
    }

    // 获取已下载的字节数（断点续传）
    int existingBytes = 0;
    if (await tempFile.exists()) {
      existingBytes = await tempFile.length();
    }

    // 如果已经下载完成
    if (existingBytes >= segment.expectedSize) {
      await _finalizeDownload(tempFile, finalFile, segment);
      return true;
    }

    final downloadStart = segment.startByte + existingBytes;
    final downloadEnd = segment.endByte;

    segment.updateStatus(SegmentStatus.downloading);
    log(() => 'Starting download: $segment from byte $downloadStart');

    HttpClient? client;
    RandomAccessFile? raf;

    try {
      client = createHttpClient();
      final request = await client.getUrl(Uri.parse(mediaUrl));

      // 🔑 注入自定义 Headers
      if (headers != null && headers.isNotEmpty) {
        headers.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=$downloadStart-$downloadEnd',
      );

      final response = await request.close();

      if (response.statusCode != HttpStatus.partialContent &&
          response.statusCode != HttpStatus.ok) {
        log(() => 'HTTP error ${response.statusCode} for: $segment');
        segment.updateStatus(SegmentStatus.failed);
        return false;
      }

      // 打开文件进行追加写入
      raf = await tempFile.open(mode: FileMode.append);

      int totalDownloaded = existingBytes;
      int chunkCount = 0;

      // 读超时：切换网络后旧连接可能挂起不报错，超时后抛 TimeoutException 以便重试并释放槽位
      final timeoutDuration = Duration(
        seconds: MediaProxyConfig.instance.httpStreamReadTimeoutSeconds,
      );

      await for (final chunk in response.timeout(timeoutDuration)) {
        if (cancelToken?.call() == true) {
          log(() => 'Download cancelled: $segment');
          await raf?.flush();
          segment.updateStatus(SegmentStatus.pending);
          return false;
        }

        try {
          await raf?.writeFrom(chunk);
        } catch (e) {
          // 磁盘空间不足保护
          if (e.toString().contains('No space left on device') ||
              e.toString().contains('OS Error: 28')) {
            log(() => 'CRITICAL: Disk full while writing $segment');
            await raf?.close();
            raf = null;
            await closeHttpClientSafely(client);
            // 抛出特定异常供上层捕获
            throw const FileSystemException('No space left on device');
          }
          rethrow;
        }

        totalDownloaded += chunk.length;
        segment.downloadedBytes = totalDownloaded;
        chunkCount++;

        // 每10个chunk刷新一次
        if (chunkCount % 10 == 0) {
          await raf?.flush();
          segment.notifyDataAvailable();
        }

        onProgress?.call(totalDownloaded);
      }

      // 最终刷新
      await raf?.flush();
      await raf?.close();
      raf = null;

      // 🔑 必须校验：只有写满预期字节才标记完成，否则末尾分片会缺数据导致“最后几秒播不到”
      if (totalDownloaded < segment.expectedSize) {
        log(
          () =>
              'Segment incomplete: got $totalDownloaded, need ${segment.expectedSize}, will retry: $segment',
        );
        segment.downloadedBytes = totalDownloaded;
        segment.updateStatus(SegmentStatus.failed);
        return false;
      }

      await _finalizeDownload(tempFile, finalFile, segment);

      log(() => 'Segment completed: $segment');
      return true;
    } catch (e) {
      if (e is TimeoutException) {
        log(
          () =>
              'Stream read timeout (no data for ${MediaProxyConfig.instance.httpStreamReadTimeoutSeconds}s), may be network switch: $segment',
        );
      } else {
        log(() => 'Download error: $e');
      }
      segment.updateStatus(SegmentStatus.failed);
      return false;
    } finally {
      await raf?.close();
      await closeHttpClientSafely(client);
    }
  }

  /// 完成下载（重命名临时文件）
  static Future<void> _finalizeDownload(
    File tempFile,
    File finalFile,
    MediaSegment segment,
  ) async {
    try {
      // 🔑 处理并发下载：如果 finalFile 已存在且大小正确，说明另一个下载已完成
      if (await finalFile.exists()) {
        final finalSize = await finalFile.length();
        if (finalSize >= segment.expectedSize) {
          log(
            () =>
                'Segment already finalized by another download: ${segment.startByte ~/ 1024 ~/ 1024}MB',
          );
          segment.downloadedBytes = finalSize;
          segment.updateStatus(SegmentStatus.completed);
          segment.notifyDataAvailable();
          // 清理可能存在的 tempFile
          if (await tempFile.exists()) {
            try {
              await tempFile.delete();
            } catch (_) {}
          }
          return;
        }
      }

      if (await tempFile.exists()) {
        // 🔑 最终验证：确保文件大小正确
        final tempSize = await tempFile.length();
        if (tempSize < segment.expectedSize) {
          log(
            () =>
                'Final validation failed: file size $tempSize < expected ${segment.expectedSize}',
          );
          segment.updateStatus(SegmentStatus.failed);
          return;
        }

        // 如果目标文件已存在，先删除
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await tempFile.rename(finalFile.path);

        // 确保 downloadedBytes 正确
        segment.downloadedBytes = segment.expectedSize;
        segment.updateStatus(SegmentStatus.completed);
        segment.notifyDataAvailable();
      } else {
        // tempFile 不存在，检查 finalFile 是否已被另一个下载处理
        log(
          () =>
              'Temp file not found, segment may have been finalized elsewhere',
        );
        // 不标记为 completed，让调用方处理
      }
    } catch (e) {
      log(() => 'Error finalizing download: $e');
      rethrow;
    }
  }
}
