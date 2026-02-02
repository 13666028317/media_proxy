// =============================================================================
// SegmentDownloader - 分片下载器（优化版）
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'constants.dart';
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
    void Function(int downloadedBytes)? onProgress,
    bool Function()? cancelToken,
  }) async {
    int retryCount = 0;
    int delay = kDownloadRetryInitialDelayMs;

    while (retryCount < kDownloadRetryCount) {
      try {
        final result = await _downloadSegmentInternal(
          mediaUrl: mediaUrl,
          segment: segment,
          cacheDir: cacheDir,
          onProgress: onProgress,
          cancelToken: cancelToken,
        );
        if (result) return true;
      } catch (e) {
        log(() =>
            'Download attempt ${retryCount + 1}/$kDownloadRetryCount failed: $e');
      }

      retryCount++;
      if (retryCount < kDownloadRetryCount) {
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
    void Function(int downloadedBytes)? onProgress,
    bool Function()? cancelToken,
  }) async {
    final tempFile = segment.getTempFile(cacheDir);
    final finalFile = segment.getSegmentFile(cacheDir);

    // 检查是否已下载完成
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

      await for (final chunk in response) {
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

      await _finalizeDownload(tempFile, finalFile, segment);

      log(() => 'Segment completed: $segment');
      return true;
    } catch (e) {
      log(() => 'Download error: $e');
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
      if (await tempFile.exists()) {
        // 如果目标文件已存在，先删除
        if (await finalFile.exists()) {
          await finalFile.delete();
        }
        await tempFile.rename(finalFile.path);
      }

      segment.updateStatus(SegmentStatus.completed);
      segment.notifyDataAvailable();
    } catch (e) {
      log(() => 'Error finalizing download: $e');
      rethrow;
    }
  }
}
