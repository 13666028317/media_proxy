// =============================================================================
// PlayerSession - 播放器会话
// =============================================================================

import 'dart:io';

import 'download_task.dart';
import 'media_segment.dart';

/// 播放器会话
///
/// 代表一个播放器的请求会话，管理该会话的状态和输出
class PlayerSession {
  /// 唯一会话ID
  final String sessionId;

  /// 关联的下载任务
  final MediaDownloadTask task;

  /// HTTP请求
  final HttpRequest request;

  /// 请求的起始字节
  final int rangeStart;

  /// 请求的结束字节
  final int rangeEnd;

  /// 是否已关闭
  bool _isClosed = false;

  /// 当前正在等待的分片
  MediaSegment? _currentWaitingSegment;

  PlayerSession({
    required this.sessionId,
    required this.task,
    required this.request,
    required this.rangeStart,
    required this.rangeEnd,
  });

  /// 是否已关闭
  bool get isClosed => _isClosed;

  /// 关闭会话
  void close() {
    _isClosed = true;
  }

  /// 标记当前等待的分片
  void setWaitingSegment(MediaSegment? segment) {
    _currentWaitingSegment = segment;
  }

  /// 获取当前等待的分片
  MediaSegment? get currentWaitingSegment => _currentWaitingSegment;
}
