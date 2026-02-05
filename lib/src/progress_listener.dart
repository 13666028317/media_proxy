// =============================================================================
// 进度监听组件
// =============================================================================

import 'dart:async';

import 'download_manager.dart';
import 'utils.dart';

/// 下载进度信息
class DownloadProgressInfo {
  /// 媒体URL
  final String mediaUrl;

  /// 下载进度 (0.0 - 1.0)
  final double progress;

  /// 已下载的字节数
  final int downloadedBytes;

  /// 媒体总大小（字节）
  final int totalBytes;

  /// 已完成的分片数
  final int completedSegments;

  /// 总分片数
  final int totalSegments;

  /// 是否已完全下载
  final bool isCompleted;

  /// 下载速度（字节/秒），如果无法计算则为 null
  final int? speedBytesPerSecond;

  DownloadProgressInfo({
    required this.mediaUrl,
    required this.progress,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.completedSegments,
    required this.totalSegments,
    required this.isCompleted,
    this.speedBytesPerSecond,
  });

  /// 格式化的进度百分比
  String get progressPercent => '${(progress * 100).toStringAsFixed(1)}%';

  /// 格式化的已下载大小
  String get downloadedMB =>
      '${(downloadedBytes / 1024 / 1024).toStringAsFixed(2)} MB';

  /// 格式化的总大小
  String get totalMB => '${(totalBytes / 1024 / 1024).toStringAsFixed(2)} MB';

  /// 格式化的下载速度
  String? get speedFormatted {
    if (speedBytesPerSecond == null) return null;
    if (speedBytesPerSecond! > 1024 * 1024) {
      return '${(speedBytesPerSecond! / 1024 / 1024).toStringAsFixed(2)} MB/s';
    } else if (speedBytesPerSecond! > 1024) {
      return '${(speedBytesPerSecond! / 1024).toStringAsFixed(2)} KB/s';
    } else {
      return '$speedBytesPerSecond B/s';
    }
  }

  @override
  String toString() =>
      'DownloadProgress($progressPercent, $downloadedMB / $totalMB, segments: $completedSegments/$totalSegments)';
}

/// 内部辅助类：进度采样点
class _ProgressSample {
  final DateTime time;
  final int bytes;
  _ProgressSample(this.time, this.bytes);
}

/// 媒体下载进度监听器
///
/// 提供实时的下载进度监听功能
class MediaDownloadProgressListener {
  /// 监听媒体下载进度
  ///
  /// [mediaUrl] 原始媒体URL
  /// [intervalMs] 轮询间隔（毫秒），默认 500ms
  ///
  /// 返回一个 Stream，持续发出 DownloadProgressInfo
  /// 当媒体完全下载后，Stream 会自动关闭
  static Stream<DownloadProgressInfo> listen(
    String mediaUrl, {
    Map<String, String>? headers,
    int intervalMs = 500,
  }) async* {
    // 🔑 优化：滑动窗口采样点（存储时间戳和字节数对）
    final samples = <_ProgressSample>[];
    const windowDuration = Duration(seconds: 3);

    final task = await MediaDownloadManager().getOrCreateTask(
      mediaUrl,
      headers: headers,
    );

    while (true) {
      try {
        final segments = task.segments;
        final completedSegments = segments.where((s) => s.isCompleted).length;
        final totalSegments = segments.length;

        if (totalSegments == 0 && task.contentLength > 0) {
          await Future.delayed(Duration(milliseconds: intervalMs));
          continue;
        }

        int downloadedBytes = 0;
        for (final seg in segments) {
          downloadedBytes += seg.isCompleted
              ? seg.expectedSize
              : seg.downloadedBytes;
        }

        // 🔑 优化：滑动窗口平均速度算法
        final now = DateTime.now();
        samples.add(_ProgressSample(now, downloadedBytes));

        // 移除过期的采样点
        samples.removeWhere((s) => now.difference(s.time) > windowDuration);

        int? speed;
        if (samples.length >= 2) {
          final first = samples.first;
          final last = samples.last;
          final timeDiff = last.time.difference(first.time).inMilliseconds;
          if (timeDiff > 0) {
            final bytesDiff = last.bytes - first.bytes;
            speed = (bytesDiff * 1000 / timeDiff).round();
            if (speed < 0) speed = 0;
          }
        }

        yield DownloadProgressInfo(
          mediaUrl: mediaUrl,
          progress: task.downloadProgress,
          downloadedBytes: downloadedBytes,
          totalBytes: task.contentLength > 0 ? task.contentLength : 0,
          completedSegments: completedSegments,
          totalSegments: totalSegments,
          isCompleted: task.isFullyDownloaded,
          speedBytesPerSecond: speed,
        );

        if (task.isFullyDownloaded) break;
      } catch (e) {
        log(() => 'Progress listener error: $e');
        break;
      }

      await Future.delayed(Duration(milliseconds: intervalMs));
    }
  }

  /// 便捷的进度监听方法
  ///
  /// [mediaUrl] 原始媒体URL
  /// [onProgress] 进度回调
  /// [onComplete] 完成回调
  /// [onError] 错误回调
  /// [intervalMs] 轮询间隔
  static Future<void> onProgress(
    String mediaUrl, {
    Map<String, String>? headers,
    required void Function(DownloadProgressInfo info) onProgress,
    void Function()? onComplete,
    void Function(Object error)? onError,
    int intervalMs = 500,
  }) async {
    try {
      await for (final info in listen(
        mediaUrl,
        headers: headers,
        intervalMs: intervalMs,
      )) {
        onProgress(info);
        if (info.isCompleted) {
          onComplete?.call();
          break;
        }
      }
    } catch (e) {
      onError?.call(e);
    }
  }

  /// 获取当前下载进度（单次查询）
  ///
  /// [mediaUrl] 原始媒体URL
  /// [headers] 自定义请求头
  static Future<DownloadProgressInfo?> getProgress(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final task = await MediaDownloadManager().getOrCreateTask(
        mediaUrl,
        headers: headers,
      );

      final segments = task.segments;
      final completedSegments = segments.where((s) => s.isCompleted).length;
      final totalSegments = segments.length;

      int downloadedBytes = 0;
      for (final seg in segments) {
        if (seg.isCompleted) {
          downloadedBytes += seg.expectedSize;
        } else {
          downloadedBytes += seg.downloadedBytes;
        }
      }

      return DownloadProgressInfo(
        mediaUrl: mediaUrl,
        progress: task.downloadProgress,
        downloadedBytes: downloadedBytes,
        totalBytes: task.contentLength > 0 ? task.contentLength : 0,
        completedSegments: completedSegments,
        totalSegments: totalSegments,
        isCompleted: task.isFullyDownloaded,
      );
    } catch (e) {
      log(() => 'Get progress error: $e');
      return null;
    }
  }
}
