// =============================================================================
// MediaSegment - 媒体分片信息
// =============================================================================

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'enums.dart';

/// 媒体分片信息类
///
/// 每个分片代表媒体文件的一个连续字节范围
/// 分片是下载和缓存的最小单位
class MediaSegment {
  /// 分片在媒体中的起始字节位置（包含）
  final int startByte;

  /// 分片在媒体中的结束字节位置（包含）
  final int endByte;

  /// 分片的当前状态
  SegmentStatus status;

  /// 实际已下载的字节数
  int downloadedBytes;

  /// 最后一次状态更新的时间戳
  DateTime lastUpdateTime;

  /// 通知流（用于通知等待者数据可用）
  final _dataAvailableController = StreamController<void>.broadcast();

  MediaSegment({
    required this.startByte,
    required this.endByte,
    this.status = SegmentStatus.pending,
    this.downloadedBytes = 0,
  }) : lastUpdateTime = DateTime.now();

  /// 分片的预期总大小
  int get expectedSize => endByte - startByte + 1;

  /// 分片是否已完成下载
  bool get isCompleted => status == SegmentStatus.completed;

  /// 分片是否正在下载
  bool get isDownloading => status == SegmentStatus.downloading;

  /// 分片是否可以开始下载
  bool get canStartDownload =>
      status == SegmentStatus.pending || status == SegmentStatus.failed;

  /// 获取分片文件的路径
  File getSegmentFile(Directory cacheDir) {
    return File(p.join(cacheDir.path, '${startByte}_$endByte.seg'));
  }

  /// 获取临时下载文件的路径
  File getTempFile(Directory cacheDir) {
    return File(p.join(cacheDir.path, '${startByte}_$endByte.tmp'));
  }

  /// 通知有新数据可用
  void notifyDataAvailable() {
    if (!_dataAvailableController.isClosed) {
      _dataAvailableController.add(null);
    }
  }

  /// 等待数据可用
  Future<void> waitForData() async {
    if (isCompleted) return;
    await _dataAvailableController.stream.first;
  }

  /// 更新状态并刷新时间戳
  void updateStatus(SegmentStatus newStatus) {
    status = newStatus;
    lastUpdateTime = DateTime.now();
    if (newStatus == SegmentStatus.completed) {
      notifyDataAvailable();
    }
  }

  /// 关闭通知流
  void dispose() {
    _dataAvailableController.close();
  }

  /// 序列化为JSON
  Map<String, dynamic> toJson() => {
    'startByte': startByte,
    'endByte': endByte,
    'status': status.index,
    'downloadedBytes': downloadedBytes,
    'lastUpdateTime': lastUpdateTime.millisecondsSinceEpoch,
  };

  /// 从JSON反序列化
  factory MediaSegment.fromJson(Map<String, dynamic> json) {
    final segment = MediaSegment(
      startByte: json['startByte'] as int,
      endByte: json['endByte'] as int,
      status: SegmentStatus.values[json['status'] as int? ?? 0],
      downloadedBytes: json['downloadedBytes'] as int? ?? 0,
    );

    // 恢复时将"正在下载"状态重置为"等待"
    if (segment.status == SegmentStatus.downloading) {
      segment.status = SegmentStatus.pending;
    }

    return segment;
  }

  @override
  String toString() =>
      'Segment[$startByte-$endByte, ${status.name}, ${downloadedBytes}B]';
}
