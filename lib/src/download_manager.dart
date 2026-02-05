// =============================================================================
// MediaDownloadManager - 全局下载管理器
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'cache_strategy.dart';
import 'constants.dart';
import 'download_queue.dart';
import 'download_task.dart';
import 'utils.dart';

/// 缓存信息类（内部使用）已被 CacheEntry 替代
// class _CacheInfo { ... }

/// 全局下载管理器（单例）
class MediaDownloadManager {
  static final MediaDownloadManager _instance =
      MediaDownloadManager._internal();
  factory MediaDownloadManager() => _instance;
  MediaDownloadManager._internal();

  final Map<String, MediaDownloadTask> _tasks = {};
  Map<String, MediaDownloadTask> get tasks => _tasks;
  final Map<String, Completer<MediaDownloadTask>> _pendingTasks = {};
  Directory? _cacheRoot;

  /// 获取缓存根目录
  Future<Directory> getCacheRoot() async {
    if (_cacheRoot != null) return _cacheRoot!;

    final appSupport = await getApplicationSupportDirectory();
    _cacheRoot = Directory(p.join(appSupport.path, 'media_cache'));

    if (!await _cacheRoot!.exists()) {
      await _cacheRoot!.create(recursive: true);
    }

    return _cacheRoot!;
  }

  /// 获取或创建下载任务
  Future<MediaDownloadTask> getOrCreateTask(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    // 🔑 统一任务 Key（考虑 Headers 差异）
    final headersString = canonicalizeHeaders(headers);
    final taskKey = headersString.isEmpty
        ? mediaUrl
        : '$mediaUrl|$headersString';

    // 检查内存中是否已存在
    if (_tasks.containsKey(taskKey)) {
      final task = _tasks[taskKey]!;
      task.updateAccessTime();
      return task;
    }

    // 检查是否有正在创建中的任务
    if (_pendingTasks.containsKey(taskKey)) {
      log(() => 'Waiting for pending task: $mediaUrl');
      return _pendingTasks[taskKey]!.future;
    }

    // 创建锁，开始创建任务
    final completer = Completer<MediaDownloadTask>();
    _pendingTasks[taskKey] = completer;

    try {
      // 自动缓存清理
      if (kEnableAutoCacheCleanup) {
        await _autoCleanupIfNeeded();
      }

      final cacheRoot = await getCacheRoot();

      // 使用任务 Key 的哈希作为目录名
      final urlHash = computeMd5Hash(taskKey);
      final cacheDir = Directory(p.join(cacheRoot.path, urlHash));

      final task = MediaDownloadTask(
        mediaUrl: mediaUrl,
        cacheDir: cacheDir,
        requestHeaders: headers,
      );

      await task.initialize();
      task.updateAccessTime();

      _tasks[taskKey] = task;
      completer.complete(task);
      return task;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingTasks.remove(taskKey);
    }
  }

  /// 自动清理缓存
  Future<void> _autoCleanupIfNeeded() async {
    try {
      // 1. 清理过期临时文件
      await _cleanupExpiredTempFiles();

      // 2. 清理缓存大小
      final currentSize = await getCacheSize();
      if (currentSize > kDefaultMaxCacheSize) {
        log(
          () =>
              'Cache size ($currentSize) exceeds limit ($kDefaultMaxCacheSize), cleaning...',
        );
        await cleanupCacheLRU(kDefaultMaxCacheSize);
      }
    } catch (e) {
      log(() => 'Auto cleanup failed: $e');
    }
  }

  /// 清理超过 24 小时的临时文件 (.tmp)
  Future<void> _cleanupExpiredTempFiles() async {
    try {
      final cacheRoot = await getCacheRoot();
      if (!await cacheRoot.exists()) return;

      final now = DateTime.now();
      final expiry = const Duration(hours: 24);
      int deletedCount = 0;

      await for (final entity in cacheRoot.list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.tmp')) {
          final stat = await entity.stat();
          if (now.difference(stat.modified) > expiry) {
            await entity.delete();
            deletedCount++;
          }
        }
      }

      if (deletedCount > 0) {
        log(() => 'Cleaned $deletedCount expired temp files');
      }
    } catch (e) {
      log(() => 'Temp file cleanup failed: $e');
    }
  }

  /// 使用策略清理缓存 (默认 TTL + LRU)
  Future<void> cleanupCacheLRU(
    int maxSize, {
    CacheEvictionPolicy? policy,
  }) async {
    final cacheRoot = await getCacheRoot();
    if (!await cacheRoot.exists()) return;

    final cacheInfoList = <CacheEntry>[]; // 使用新的通用 CacheEntry

    await for (final entity in cacheRoot.list()) {
      if (entity is Directory) {
        final configFile = File(p.join(entity.path, 'config.json'));
        if (await configFile.exists()) {
          try {
            final content = await configFile.readAsString();
            final json = jsonDecode(content) as Map<String, dynamic>;

            int dirSize = 0;
            await for (final file in entity.list()) {
              if (file is File) {
                dirSize += await file.length();
              }
            }

            final lastAccessMs = json['lastAccessTime'] as int? ?? 0;
            // 获取 MediaURL (如果 config 中没有，尝试用目录名反推或忽略)
            // 注意：因为是 Hash 目录，反推很难。建议在 config.json 增加 url 字段，或者这里暂时用 hash 代替
            // 在之前的重构中，我们在 saveConfig 时并没有保存 url，这需要修正，或者我们接受这里用 path
            // 让我们假设 task 已经初始化过，我们用 hash 也没关系，因为删除是基于 path 的

            cacheInfoList.add(
              CacheEntry(
                directory: entity,
                lastAccessTime: DateTime.fromMillisecondsSinceEpoch(
                  lastAccessMs,
                ),
                sizeBytes: dirSize,
                mediaUrl: 'hash:${p.basename(entity.path)}', // 占位符
              ),
            );
          } catch (e) {
            log(() => 'Corrupted cache, deleting: ${entity.path}');
            await entity.delete(recursive: true);
          }
        }
      }
    }

    // 使用策略引擎选择要删除的文件
    final activePolicy = policy ?? SmartCachePolicy(maxSizeBytes: maxSize);
    int currentSize = cacheInfoList.fold(
      0,
      (sum, info) => sum + info.sizeBytes,
    );

    // 执行策略筛选
    final toDelete = activePolicy.selectFilesToEvict(
      currentSize,
      cacheInfoList,
    );

    log(
      () =>
          'Cache cleanup: current=${currentSize ~/ 1024 ~/ 1024}MB, evicting ${toDelete.length} items',
    );

    for (final info in toDelete) {
      final isActive = _tasks.values.any(
        (task) =>
            task.cacheDir.path == info.directory.path && task.hasActiveSessions,
      );

      if (!isActive) {
        log(
          () => 'Deleting cache: ${info.directory.path} (${info.sizeBytes}B)',
        );

        _tasks.removeWhere(
          (_, task) => task.cacheDir.path == info.directory.path,
        );
        await info.directory.delete(recursive: true);
        currentSize -= info.sizeBytes;
      } else {
        log(() => 'Skipping active cache eviction: ${info.directory.path}');
      }
    }

    log(
      () =>
          'Cache cleanup completed: new size=${currentSize ~/ 1024 ~/ 1024}MB',
    );
  }

  /// 移除任务（当没有活跃会话时）
  Future<void> removeTaskIfInactive(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    final headersString = canonicalizeHeaders(headers);
    final taskKey = headersString.isEmpty
        ? mediaUrl
        : '$mediaUrl|$headersString';

    final task = _tasks[taskKey];
    if (task != null && !task.hasActiveSessions) {
      GlobalDownloadQueue().cancelMedia(mediaUrl);
      await task.forceFlushConfig();
      _tasks.remove(taskKey);
      task.dispose();
      log(() => 'Task removed from memory: $mediaUrl (cache files preserved)');
    }
  }

  /// 清除所有缓存
  Future<void> clearAllCache() async {
    for (final task in _tasks.values) {
      task.cancel();
      task.dispose();
    }
    _tasks.clear();

    final cacheRoot = await getCacheRoot();
    if (await cacheRoot.exists()) {
      await cacheRoot.delete(recursive: true);
    }

    log(() => 'All cache cleared');
  }

  /// 获取缓存大小
  Future<int> getCacheSize() async {
    final cacheRoot = await getCacheRoot();
    if (!await cacheRoot.exists()) return 0;

    int totalSize = 0;
    await for (final entity in cacheRoot.list(recursive: true)) {
      if (entity is File) {
        totalSize += await entity.length();
      }
    }
    return totalSize;
  }
}
