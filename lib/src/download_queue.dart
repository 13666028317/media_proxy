// =============================================================================
// GlobalDownloadQueue - 全局下载队列管理器
// =============================================================================

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'config.dart';
import 'download_manager.dart';
import 'media_segment.dart';
import 'segment_downloader.dart';
import 'utils.dart';

/// 下载任务项
class _DownloadItem {
  final String mediaUrl;
  final MediaSegment segment;
  final Directory cacheDir;
  final Map<String, String>? headers;
  final int priority;
  final DateTime createdAt;
  final bool Function()? cancelToken;
  final void Function(bool success)? onComplete;
  final void Function(int bytes)? onProgress;
  bool _cancelled = false;

  _DownloadItem({
    required this.mediaUrl,
    required this.segment,
    required this.cacheDir,
    this.headers,
    required this.priority,
    this.cancelToken,
    this.onComplete,
    this.onProgress,
  }) : createdAt = DateTime.now();

  void cancel() => _cancelled = true;
  bool get isCancelled => _cancelled || (cancelToken?.call() ?? false);
}

/// 全局下载队列管理器（单例）
class GlobalDownloadQueue {
  static final GlobalDownloadQueue _instance = GlobalDownloadQueue._internal();
  factory GlobalDownloadQueue() => _instance;
  GlobalDownloadQueue._internal();

  final Queue<_DownloadItem> _pendingQueue = Queue<_DownloadItem>();
  final Map<String, _DownloadItem> _activeDownloads = {};
  final Map<String, int> _mediaActiveCount = {};
  String? _currentPlayingUrl;

  /// 起播独占锁计数器：URL -> 活跃的起播请求数
  final Map<String, int> _startupLocks = {};
  bool _isProcessing = false;

  SegmentDownloader _downloader = HttpSegmentDownloader();

  /// 设置下载器（用于测试或自定义）
  set downloader(SegmentDownloader downloader) {
    _downloader = downloader;
  }

  /// 获取当前正在播放的媒体 URL
  String? get currentPlayingUrl => _currentPlayingUrl;

  /// 设置当前正在播放的媒体
  void setCurrentPlaying(String? mediaUrl) {
    if (_currentPlayingUrl == mediaUrl) return;

    final oldUrl = _currentPlayingUrl;
    _currentPlayingUrl = mediaUrl;

    log(
      () =>
          'Current playing changed: ${oldUrl ?? 'none'} → ${mediaUrl ?? 'none'}',
    );

    if (mediaUrl != null) {
      _boostPriority(mediaUrl, MediaProxyConfig.instance.priorityPlaying);

      if (MediaProxyConfig.instance.pauseOldDownloadsOnSwitch &&
          oldUrl != null &&
          oldUrl != mediaUrl) {
        _lowerPriority(oldUrl, MediaProxyConfig.instance.priorityBackground);
      }
    }

    _processQueue();
  }

  /// 添加下载任务到队列
  void enqueue({
    required String mediaUrl,
    required MediaSegment segment,
    required Directory cacheDir,
    Map<String, String>? headers,
    int? priority,
    bool Function()? cancelToken,
    void Function(bool success)? onComplete,
    void Function(int bytes)? onProgress,
  }) {
    // 🔑 防止重复入队：检查分片是否已完成、正在下载、或已在队列中
    if (segment.isCompleted) {
      log(
        () =>
            'Skip enqueue: segment already completed: ${segment.startByte ~/ 1024 ~/ 1024}MB',
      );
      onComplete?.call(true);
      return;
    }

    if (segment.isDownloading) {
      log(
        () =>
            'Skip enqueue: segment already downloading: ${segment.startByte ~/ 1024 ~/ 1024}MB',
      );
      return;
    }

    // 检查是否已在队列中
    final key = '${mediaUrl}_${segment.startByte}';
    final alreadyInQueue = _pendingQueue.any(
      (item) =>
          item.mediaUrl == mediaUrl &&
          item.segment.startByte == segment.startByte,
    );
    final alreadyActive = _activeDownloads.containsKey(key);

    if (alreadyInQueue || alreadyActive) {
      log(
        () =>
            'Skip enqueue: segment already in queue/active: ${segment.startByte ~/ 1024 ~/ 1024}MB',
      );
      return;
    }

    // 🔑 修复：当前播放媒体时，使用传入优先级和 kPriority Playing 的较大值
    // 这样 kPriorityPlayingUrgent(200) 不会被降级为 kPriorityPlaying(100)
    final resolvedPriority =
        priority ?? MediaProxyConfig.instance.priorityBackground;
    final playingPriority = MediaProxyConfig.instance.priorityPlaying;

    final actualPriority = (mediaUrl == _currentPlayingUrl)
        ? (resolvedPriority > playingPriority
              ? resolvedPriority
              : playingPriority)
        : resolvedPriority;

    final item = _DownloadItem(
      mediaUrl: mediaUrl,
      segment: segment,
      cacheDir: cacheDir,
      headers: headers,
      priority: actualPriority,
      cancelToken: cancelToken,
      onComplete: onComplete,
      onProgress: onProgress,
    );

    _insertByPriority(item);

    log(
      () =>
          'Enqueued: ${segment.startByte ~/ 1024 ~/ 1024}MB of $mediaUrl '
          '(priority: $actualPriority, queue: ${_pendingQueue.length})',
    );

    _processQueue();
  }

  /// 按优先级插入队列（优先级高的排前面）
  void _insertByPriority(_DownloadItem item) {
    if (_pendingQueue.isEmpty) {
      _pendingQueue.add(item);
      return;
    }

    // 🔑 修复：使用 toList() 遍历，正确查找插入位置
    // 找到第一个优先级低于新任务的位置
    final list = _pendingQueue.toList();
    int insertIndex = list.length; // 默认插入末尾

    for (int i = 0; i < list.length; i++) {
      if (list[i].priority < item.priority) {
        insertIndex = i;
        break;
      }
    }

    // 重建队列
    _pendingQueue.clear();
    for (int i = 0; i < list.length; i++) {
      if (i == insertIndex) {
        _pendingQueue.add(item);
      }
      _pendingQueue.add(list[i]);
    }
    // 如果插入位置在末尾
    if (insertIndex == list.length) {
      _pendingQueue.add(item);
    }
  }

  /// 提升特定媒体的优先级
  void _boostPriority(String mediaUrl, int newPriority) {
    final items = _pendingQueue
        .where((item) => item.mediaUrl == mediaUrl)
        .toList();

    _pendingQueue.removeWhere((item) => item.mediaUrl == mediaUrl);

    for (final item in items) {
      _insertByPriority(
        _DownloadItem(
          mediaUrl: item.mediaUrl,
          segment: item.segment,
          cacheDir: item.cacheDir,
          priority: newPriority,
          cancelToken: item.cancelToken,
          onComplete: item.onComplete,
          onProgress: item.onProgress,
        ),
      );
    }

    log(
      () =>
          'Boosted priority for $mediaUrl to $newPriority (${items.length} items)',
    );
  }

  /// 降低特定媒体的优先级
  void _lowerPriority(String mediaUrl, int newPriority) {
    final items = _pendingQueue
        .where((item) => item.mediaUrl == mediaUrl)
        .toList();

    _pendingQueue.removeWhere((item) => item.mediaUrl == mediaUrl);

    for (final item in items) {
      _insertByPriority(
        _DownloadItem(
          mediaUrl: item.mediaUrl,
          segment: item.segment,
          cacheDir: item.cacheDir,
          priority: newPriority,
          cancelToken: item.cancelToken,
          onComplete: item.onComplete,
          onProgress: item.onProgress,
        ),
      );
    }

    log(
      () =>
          'Lowered priority for $mediaUrl to $newPriority (${items.length} items)',
    );
  }

  /// 取消特定媒体的所有下载任务
  void cancelMedia(String mediaUrl, {bool cancelActive = true}) {
    final toCancel = _pendingQueue
        .where((item) => item.mediaUrl == mediaUrl)
        .toList();
    _pendingQueue.removeWhere((item) => item.mediaUrl == mediaUrl);

    for (final item in toCancel) {
      item.onComplete?.call(false);
    }

    if (cancelActive) {
      _activeDownloads.forEach((key, item) {
        if (item.mediaUrl == mediaUrl) {
          item.cancel();
        }
      });
    }

    log(
      () =>
          'Cancelled downloads for $mediaUrl (removed ${toCancel.length} from queue)',
    );
  }

  /// 取消所有非当前播放媒体的下载
  void cancelAllExceptCurrent() {
    if (_currentPlayingUrl == null) return;

    final toCancel = <String>{};
    for (final item in _pendingQueue) {
      if (item.mediaUrl != _currentPlayingUrl) {
        toCancel.add(item.mediaUrl);
      }
    }

    for (final url in toCancel) {
      cancelMedia(url);
    }

    log(() => 'Cancelled all downloads except current playing');
  }

  /// 暂停所有下载
  void pauseAll() {
    for (final item in _pendingQueue) {
      item.cancel();
    }
    for (final item in _activeDownloads.values) {
      item.cancel();
    }
    _pendingQueue.clear();
    log(() => 'All downloads paused');
  }

  /// 处理下载队列
  void _processQueue() {
    if (_isProcessing) return;
    _isProcessing = true;

    scheduleMicrotask(() async {
      try {
        await _doProcessQueue();
      } finally {
        _isProcessing = false;
      }
    });
  }

  /// 实际处理队列的逻辑
  Future<void> _doProcessQueue() async {
    while (_pendingQueue.isNotEmpty) {
      if (_activeDownloads.length >=
          MediaProxyConfig.instance.globalMaxConcurrentDownloads) {
        break;
      }

      // 🔑 独占期逻辑：如果存在活跃的起播锁，且当前排队的第一项不是高优任务，则暂停处理
      // 优化：阈值降至 150，允许 moov 分片在独占期内下载，防止 MP4 播放死锁
      if (_startupLocks.isNotEmpty) {
        final firstItem = _pendingQueue.firstOrNull;
        if (firstItem != null &&
            firstItem.priority <
                (MediaProxyConfig.instance.priorityPlayingUrgent - 50)) {
          log(
            () =>
                'Startup locked by ${_startupLocks.keys.first}, skipping non-urgent task (priority: ${firstItem.priority})',
          );
          break;
        }
      }

      final item = _pendingQueue.firstOrNull;

      if (item == null) break;

      final mediaActiveCount = _mediaActiveCount[item.mediaUrl] ?? 0;
      if (mediaActiveCount >=
          MediaProxyConfig.instance.perMediaMaxConcurrentDownloads) {
        final nextItem = _findNextAvailableItem();
        if (nextItem == null) break;
        _pendingQueue.remove(nextItem);
        await _startDownload(nextItem);
        continue;
      }

      if (item.isCancelled) {
        _pendingQueue.removeFirst();
        item.onComplete?.call(false);
        continue;
      }

      if (item.segment.isCompleted || item.segment.isDownloading) {
        _pendingQueue.removeFirst();
        item.onComplete?.call(item.segment.isCompleted);
        continue;
      }

      _pendingQueue.removeFirst();
      await _startDownload(item);
    }
  }

  /// 查找下一个可以下载的任务
  _DownloadItem? _findNextAvailableItem() {
    for (final item in _pendingQueue) {
      final mediaActiveCount = _mediaActiveCount[item.mediaUrl] ?? 0;
      if (mediaActiveCount <
              MediaProxyConfig.instance.perMediaMaxConcurrentDownloads &&
          !item.isCancelled) {
        return item;
      }
    }
    return null;
  }

  /// 增加或减少起播独占锁
  void updateStartupLock(String mediaUrl, bool add) {
    if (add) {
      _startupLocks[mediaUrl] = (_startupLocks[mediaUrl] ?? 0) + 1;
    } else {
      final count = (_startupLocks[mediaUrl] ?? 0) - 1;
      if (count <= 0) {
        _startupLocks.remove(mediaUrl);
      } else {
        _startupLocks[mediaUrl] = count;
      }
    }
    log(
      () =>
          'Startup lock count for $mediaUrl: ${_startupLocks[mediaUrl] ?? 0} (Total locks: ${_startupLocks.length})',
    );
    _processQueue();
  }

  /// 开始下载任务
  Future<void> _startDownload(_DownloadItem item) async {
    final key = '${item.mediaUrl}_${item.segment.startByte}';
    _activeDownloads[key] = item;
    _mediaActiveCount[item.mediaUrl] =
        (_mediaActiveCount[item.mediaUrl] ?? 0) + 1;

    log(
      () =>
          'Starting download: ${item.segment.startByte ~/ 1024 ~/ 1024}MB '
          '(active: ${_activeDownloads.length}/${MediaProxyConfig.instance.globalMaxConcurrentDownloads})',
    );

    unawaited(_executeDownload(item, key));
  }

  /// 执行下载
  Future<void> _executeDownload(_DownloadItem item, String key) async {
    bool success = false;

    try {
      success = await _downloader.downloadSegment(
        mediaUrl: item.mediaUrl,
        segment: item.segment,
        cacheDir: item.cacheDir,
        headers: item.headers,
        onProgress: item.onProgress,
        cancelToken: () => item.isCancelled,
      );
    } catch (e) {
      log(() => 'Download error: $e');
      success = false;

      // 磁盘空间不足时，触发紧急清理
      if (e is FileSystemException && e.message.contains('No space')) {
        log(
          () => 'CRITICAL: Disk full detected! Triggering emergency cleanup...',
        );
        unawaited(
          MediaDownloadManager().cleanupCacheLRU(
            MediaProxyConfig.instance.maxCacheSize ~/ 2, // 紧急情况下清理到 50%
          ),
        );
      }
    } finally {
      _activeDownloads.remove(key);
      _mediaActiveCount[item.mediaUrl] =
          (_mediaActiveCount[item.mediaUrl] ?? 1) - 1;
      if (_mediaActiveCount[item.mediaUrl] == 0) {
        _mediaActiveCount.remove(item.mediaUrl);
      }

      item.onComplete?.call(success);
      _processQueue();
    }
  }

  /// 获取队列状态信息
  Map<String, dynamic> getQueueStats() {
    final mediaStats = <String, int>{};
    for (final item in _pendingQueue) {
      mediaStats[item.mediaUrl] = (mediaStats[item.mediaUrl] ?? 0) + 1;
    }

    return {
      'pendingCount': _pendingQueue.length,
      'activeCount': _activeDownloads.length,
      'globalMax': MediaProxyConfig.instance.globalMaxConcurrentDownloads,
      'currentPlaying': _currentPlayingUrl,
      'mediaStats': mediaStats,
    };
  }
}
