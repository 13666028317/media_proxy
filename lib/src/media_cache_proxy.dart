// =============================================================================
// MediaCacheProxy - 核心代理服务器
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'constants.dart';
import 'download_manager.dart';
import 'download_queue.dart';
import 'enums.dart';
import 'media_segment.dart';
import 'player_session.dart';
import 'preload_scheduler.dart';
import 'utils.dart';

/// 媒体缓存代理服务器
///
/// 主入口类，提供本地HTTP代理服务
class MediaCacheProxy {
  static MediaCacheProxy? _instance;
  HttpServer? _server;
  int? _port;
  Completer<String>? _startingCompleter;
  final Map<String, PlayerSession> _sessions = {};
  final MediaDownloadManager _downloadManager = MediaDownloadManager();

  MediaCacheProxy._internal();

  static MediaCacheProxy get instance {
    _instance ??= MediaCacheProxy._internal();
    return _instance!;
  }

  /// 启动代理服务器
  static Future<String> start() => instance._start();

  Future<String> _start() async {
    if (_server != null && _port != null) {
      return 'http://127.0.0.1:$_port';
    }

    if (_startingCompleter != null) {
      log(() => 'Proxy is starting, waiting...');
      return _startingCompleter!.future;
    }

    _startingCompleter = Completer<String>();

    try {
      _server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        0,
        shared: true,
      );
      _port = _server!.port;

      _server!.listen(
        _handleRequest,
        onError: (error) => log(() => 'Server error: $error'),
        onDone: () => log(() => 'Server stopped'),
      );

      final url = 'http://127.0.0.1:$_port';
      log(() => 'Proxy started at $url');

      _startingCompleter!.complete(url);
      return url;
    } catch (e) {
      _startingCompleter!.completeError(e);
      rethrow;
    } finally {
      _startingCompleter = null;
    }
  }

  /// 停止代理服务器
  static Future<void> stop() => instance._stop();

  Future<void> _stop() async {
    for (final session in _sessions.values) {
      session.close();
    }
    _sessions.clear();

    await _server?.close(force: true);
    _server = null;
    _port = null;

    log(() => 'Proxy stopped');
  }

  /// 获取代理URL
  static Future<String> getProxyUrl(
    String originalUrl, {
    Map<String, String>? headers,
  }) async {
    final baseUrl = await start();
    final encodedUrl = Uri.encodeComponent(originalUrl);
    var proxyUrl = '$baseUrl/media?url=$encodedUrl';

    if (headers != null && headers.isNotEmpty) {
      final headersJson = jsonEncode(headers);
      final encodedHeaders = base64Url.encode(utf8.encode(headersJson));
      proxyUrl += '&headers=$encodedHeaders';
    }

    return proxyUrl;
  }

  /// 处理HTTP请求
  Future<void> _handleRequest(HttpRequest request) async {
    final sessionId = generateSessionId();
    log(() => '[$sessionId] Request: ${request.uri}');

    try {
      final originalUrl = request.uri.queryParameters['url'];
      if (originalUrl == null || originalUrl.isEmpty) {
        _sendError(request, HttpStatus.badRequest, 'Missing url parameter');
        return;
      }

      final decodedUrl = Uri.decodeComponent(originalUrl);
      log(() => '[$sessionId] Original URL: $decodedUrl');

      // 🔑 解析自定义 Headers
      Map<String, String>? headers;
      final headersParam = request.uri.queryParameters['headers'];
      if (headersParam != null && headersParam.isNotEmpty) {
        try {
          final decodedHeadersJson = utf8.decode(
            base64Url.decode(headersParam),
          );
          final map = jsonDecode(decodedHeadersJson) as Map<String, dynamic>;
          headers = map.map((k, v) => MapEntry(k, v.toString()));
          log(() => '[$sessionId] Decoded headers: $headers');
        } catch (e) {
          log(() => '[$sessionId] Failed to decode headers: $e');
        }
      }

      final task = await _downloadManager.getOrCreateTask(
        decodedUrl,
        headers: headers,
      );
      task.addSession();

      try {
        final rangeHeader = request.headers.value(HttpHeaders.rangeHeader);
        int rangeStart = 0;
        int rangeEnd = task.contentLength - 1;

        if (rangeHeader != null) {
          final match = RegExp(r'bytes=(\d+)-(\d*)').firstMatch(rangeHeader);
          if (match != null) {
            rangeStart = int.parse(match.group(1)!);
            final endStr = match.group(2);
            if (endStr != null && endStr.isNotEmpty) {
              rangeEnd = int.parse(endStr);
            }
          }
        }

        if (task.contentLength > 0) {
          rangeEnd = min(rangeEnd, task.contentLength - 1);
        }

        log(() => '[$sessionId] Range: $rangeStart-$rangeEnd');

        final session = PlayerSession(
          sessionId: sessionId,
          task: task,
          request: request,
          rangeStart: rangeStart,
          rangeEnd: rangeEnd,
        );
        _sessions[sessionId] = session;

        await _serveMedia(session);
      } finally {
        task.removeSession();
        _sessions.remove(sessionId);
        await _downloadManager.removeTaskIfInactive(decodedUrl);
      }
    } catch (e, st) {
      log(() => '[$sessionId] Error: $e\n$st');
      _sendError(request, HttpStatus.internalServerError, 'Internal error');
    }
  }

  /// 发送错误响应
  void _sendError(HttpRequest request, int statusCode, String message) {
    try {
      request.response
        ..statusCode = statusCode
        ..write(message)
        ..close();
    } catch (_) {}
  }

  /// 提供媒体流
  Future<void> _serveMedia(PlayerSession session) async {
    final task = session.task;
    final response = session.request.response;

    // MP4 moov 预加载
    if (task.needsMoovOptimization &&
        task.moovAtStart == false &&
        session.rangeStart == 0) {
      log(
        () => '[${session.sessionId}] MP4 moov at end detected, preloading...',
      );
      unawaited(task.preloadMoovSegment());
    }

    final contentLength = session.rangeEnd - session.rangeStart + 1;

    response.statusCode = HttpStatus.partialContent;
    response.headers.set(HttpHeaders.contentTypeHeader, task.contentType);
    response.headers.set(HttpHeaders.acceptRangesHeader, 'bytes');
    response.headers.set(
      HttpHeaders.contentRangeHeader,
      'bytes ${session.rangeStart}-${session.rangeEnd}/${task.contentLength}',
    );
    response.headers.set(HttpHeaders.contentLengthHeader, contentLength);

    log(() => '[${session.sessionId}] Response headers set');

    final segments = task.getSegmentsForRange(
      session.rangeStart,
      session.rangeEnd,
    );
    log(() => '[${session.sessionId}] Segments needed: ${segments.length}');

    _startDownloadsForSession(session, segments);
    await _streamToPlayer(session, segments);

    try {
      await response.close();
    } catch (_) {}

    log(() => '[${session.sessionId}] Response completed');
  }

  /// 为会话启动下载
  void _startDownloadsForSession(
    PlayerSession session,
    List<MediaSegment> segments,
  ) {
    final needDownload = segments.where((s) => s.canStartDownload).toList();
    final fileSize = session.task.contentLength;
    final allSegments = session.task.segments;

    // 🔑 关键修复：无论请求范围如何，总是确保末尾分片被预加载
    // 因为播放器可能先请求开头，然后 seek 到末尾，或者播放到最后需要末尾数据
    MediaSegment? endSegment;
    if (fileSize > 0 && allSegments.isNotEmpty) {
      endSegment = allSegments.last;
      if (endSegment.canStartDownload && !needDownload.contains(endSegment)) {
        needDownload.add(endSegment);
        log(
          () =>
              '[${session.sessionId}] End segment added for preload: $endSegment',
        );
      }
    }

    // 🔑 优化：激进预取策略
    // 除了请求的分片，额外预加载后续 2 个分片，以利用并发带宽
    if (segments.isNotEmpty) {
      final lastRequestedSegment = segments.last;
      if (lastRequestedSegment.endByte < fileSize - 1) {
        final nextRangeStart = lastRequestedSegment.endByte + 1;
        final nextRangeEnd = nextRangeStart + (kDefaultSegmentSize * 2);

        final extraSegments = session.task.getSegmentsForRange(
          nextRangeStart,
          nextRangeEnd,
        );
        for (final seg in extraSegments) {
          if (seg.canStartDownload && !needDownload.contains(seg)) {
            needDownload.add(seg);
            log(() => '[${session.sessionId}] Aggressive prefetch added: $seg');
          }
        }
      }
    }

    if (needDownload.isEmpty) {
      log(() => '[${session.sessionId}] All segments ready');
      return;
    }

    GlobalDownloadQueue().setCurrentPlaying(session.task.mediaUrl);

    // 🔑 按距离播放位置排序（最近的优先）
    needDownload.sort((a, b) {
      final distA = (a.startByte - session.rangeStart).abs();
      final distB = (b.startByte - session.rangeStart).abs();
      return distA.compareTo(distB);
    });

    // 🔑 识别关键分片
    // 1. 第一播放分片 = 包含 rangeStart 的分片（播放必需）
    // 2. 末尾分片 = 文件末尾的分片（MP4 的 moov 或其他格式的结尾数据）
    final firstPlaybackSegment = needDownload.isNotEmpty
        ? needDownload.first
        : null;

    // 重新查找末尾分片（可能已经在 needDownload 中）
    MediaSegment? moovSegment;
    if (fileSize > 0) {
      moovSegment = needDownload.cast<MediaSegment?>().firstWhere(
        (s) => s != null && s.endByte >= fileSize - 1,
        orElse: () => null,
      );
    }

    log(
      () =>
          '[${session.sessionId}] Enqueuing ${needDownload.length} segments to global queue',
    );
    if (firstPlaybackSegment != null) {
      log(
        () =>
            '[${session.sessionId}] First playback segment: $firstPlaybackSegment',
      );
    }
    if (moovSegment != null && moovSegment != firstPlaybackSegment) {
      log(() => '[${session.sessionId}] Moov segment: $moovSegment');
    }

    final hasAnyCompleted = allSegments.any((s) => s.isCompleted);
    final queue = GlobalDownloadQueue();

    for (int i = 0; i < needDownload.length; i++) {
      final segment = needDownload[i];

      // 🔑 修复：正确识别关键分片
      // - 第一播放分片：最高优先级 (200)
      // - 末尾分片（moov/结尾数据）：次高优先级 (150)，必须下载
      // - 其他分片：普通优先级 (100)，首屏加载时可跳过
      final isFirstPlayback = segment == firstPlaybackSegment;
      final isEndSegment = segment == moovSegment || segment == endSegment;
      final isUrgent = isFirstPlayback || isEndSegment;

      // 如果还没首帧，且不是关键分片，暂时不排队，集中火力
      if (!hasAnyCompleted && !isUrgent) {
        log(
          () =>
              '[${session.sessionId}] Skipping prefetch for startup performance: $segment',
        );
        continue;
      }

      // 优先级：第一播放分片 > 末尾分片 > 其他
      int priority;
      if (isFirstPlayback) {
        priority = kPriorityPlayingUrgent; // 200
        // 🔑 触发起播独占期：增加计数锁
        GlobalDownloadQueue().updateStartupLock(session.task.mediaUrl, true);
      } else if (isEndSegment) {
        priority = kPriorityPlayingUrgent - 50; // 150
      } else {
        priority = kPriorityPlaying; // 100
      }

      queue.enqueue(
        mediaUrl: session.task.mediaUrl,
        segment: segment,
        cacheDir: session.task.cacheDir,
        priority: priority,
        cancelToken: () => session.isClosed || session.task.isCancelled,
        onProgress: (bytes) {
          session.task.updateSegmentStatus(
            segment,
            SegmentStatus.downloading,
            bytes,
          );
        },
        onComplete: (success) {
          if (success) {
            session.task.updateSegmentStatus(segment, SegmentStatus.completed);
          }
          // 🔑 如果是起播分片，释放计数锁
          if (isFirstPlayback) {
            GlobalDownloadQueue().updateStartupLock(
              session.task.mediaUrl,
              false,
            );
          }
        },
      );
    }
  }

  /// 流式输出到播放器
  Future<void> _streamToPlayer(
    PlayerSession session,
    List<MediaSegment> segments,
  ) async {
    final response = session.request.response;
    int currentPosition = session.rangeStart;
    final endPosition = session.rangeEnd;

    for (final segment in segments) {
      if (session.isClosed) break;

      final readStart = max(segment.startByte, currentPosition);
      final readEnd = min(segment.endByte, endPosition);

      if (readStart > readEnd) continue;

      session.setWaitingSegment(segment);

      await _streamSegmentToPlayer(
        session: session,
        segment: segment,
        readStart: readStart,
        readEnd: readEnd,
        response: response,
      );

      currentPosition = readEnd + 1;
      session.setWaitingSegment(null);
    }
  }

  /// 将单个分片流式输出
  Future<void> _streamSegmentToPlayer({
    required PlayerSession session,
    required MediaSegment segment,
    required int readStart,
    required int readEnd,
    required HttpResponse response,
  }) async {
    final file = segment.getSegmentFile(session.task.cacheDir);
    final tempFile = segment.getTempFile(session.task.cacheDir);

    final fileOffset = readStart - segment.startByte;
    final bytesToRead = readEnd - readStart + 1;
    int bytesWritten = 0;
    int redownloadAttempts = 0; // 重下载重试计数
    const maxRedownloadAttempts = 3;

    while (bytesWritten < bytesToRead && !session.isClosed) {
      File? availableFile;
      if (await file.exists()) {
        availableFile = file;
      } else if (await tempFile.exists()) {
        availableFile = tempFile;
      }

      if (availableFile != null) {
        final fileLength = await availableFile.length();
        final availableBytes = fileLength - fileOffset - bytesWritten;

        if (availableBytes > 0) {
          // 🔑 优化：增加文件打开重试逻辑，处理可能的重命名/锁定冲突
          RandomAccessFile? raf;
          int openRetry = 0;
          while (openRetry < 3) {
            try {
              raf = await availableFile.open(mode: FileMode.read);
              break;
            } catch (e) {
              openRetry++;
              if (openRetry >= 3) rethrow;
              await Future.delayed(const Duration(milliseconds: 50));
            }
          }

          if (raf != null) {
            try {
              await raf.setPosition(fileOffset + bytesWritten);
              final toRead = min(availableBytes, bytesToRead - bytesWritten);
              final chunk = await raf.read(toRead.toInt());

              if (chunk.isNotEmpty) {
                try {
                  response.add(chunk);
                  bytesWritten += chunk.length;
                } catch (e) {
                  log(() => '[${session.sessionId}] Client disconnected: $e');
                  session.close();
                  break;
                }
              }
            } finally {
              await raf.close();
            }
          }
        }
      }

      if (bytesWritten < bytesToRead) {
        if (segment.isCompleted) {
          // 🔑 修复：分片标记完成但数据不足，验证文件完整性
          final actualFile = await file.exists() ? file : tempFile;
          final actualSize = await actualFile.exists()
              ? await actualFile.length()
              : 0;
          final neededSize = fileOffset + bytesToRead;

          if (actualSize < neededSize) {
            // 文件确实不完整
            if (redownloadAttempts >= maxRedownloadAttempts) {
              log(
                () =>
                    '[${session.sessionId}] Segment still incomplete after $maxRedownloadAttempts attempts, giving up: $segment',
              );
              break;
            }

            redownloadAttempts++;
            log(
              () =>
                  '[${session.sessionId}] Segment file incomplete (have: $actualSize, need: $neededSize), re-downloading (attempt $redownloadAttempts): $segment',
            );
            segment.updateStatus(SegmentStatus.failed);

            // 触发重新下载
            GlobalDownloadQueue().enqueue(
              mediaUrl: session.task.mediaUrl,
              segment: segment,
              cacheDir: session.task.cacheDir,
              priority: kPriorityPlayingUrgent,
              cancelToken: () => session.isClosed,
              onProgress: (bytes) {
                segment.downloadedBytes = bytes;
              },
              onComplete: (success) {
                if (success) {
                  segment.updateStatus(SegmentStatus.completed);
                }
              },
            );

            // 等待重下载完成
            await segment.waitForData().timeout(
              const Duration(seconds: 15),
              onTimeout: () {},
            );
            continue;
          } else {
            // 文件完整但读取位置有问题，尝试继续读取
            await Future.delayed(const Duration(milliseconds: 50));
            continue;
          }
        }

        // 等待更多数据
        await segment.waitForData().timeout(
          const Duration(milliseconds: 500),
          onTimeout: () {},
        );
      }
    }
  }

  // ========== 静态方法 ==========

  /// 获取缓存大小
  static Future<int> getCacheSize() => instance._downloadManager.getCacheSize();

  /// 清除所有缓存
  static Future<void> clearCache() => instance._downloadManager.clearAllCache();

  /// 预加载媒体
  static Future<bool> preload(
    String mediaUrl, {
    Map<String, String>? headers,
    int segmentCount = 1,
    bool includeMoov = true,
    bool smart = false, // 🆕 新增：是否启用智能调度
  }) async {
    if (smart) {
      PreloadScheduler().schedule(
        mediaUrl,
        segmentCount: segmentCount,
        includeMoov: includeMoov,
      );
      return true; // 智能调度直接返回 true
    }

    try {
      log(() => 'Preloading media: $mediaUrl (segments: $segmentCount)');

      await start();
      final task = await instance._downloadManager.getOrCreateTask(
        mediaUrl,
        headers: headers,
      );

      if (task.contentLength <= 0) {
        log(() => 'Preload failed: could not get content length');
        return false;
      }

      final segments = task.segments;
      if (segments.isEmpty) {
        log(() => 'Preload failed: no segments available');
        return false;
      }

      final pendingSegments = <MediaSegment>[];

      for (final segment in segments.take(segmentCount)) {
        if (!segment.isCompleted) {
          pendingSegments.add(segment);
        }
      }

      if (includeMoov && segments.length > 1) {
        final lastSegment = segments.last;
        bool shouldPreloadEnd = kAlwaysPreloadEndSegment;
        String preloadReason = 'always preload end';

        if (task.isMp4Format && task.moovAtStart == false) {
          shouldPreloadEnd = true;
          preloadReason = 'MP4 moov at end detected';
        }

        if (shouldPreloadEnd &&
            !lastSegment.isCompleted &&
            !pendingSegments.contains(lastSegment)) {
          pendingSegments.add(lastSegment);
          log(() => 'Adding end segment to preload queue ($preloadReason)');
        }
      }

      if (pendingSegments.isEmpty) {
        log(() => 'Preload completed: all segments already cached');
        return true;
      }

      log(() => 'Preload queue: ${pendingSegments.length} segments');

      final completer = Completer<bool>();
      int completedCount = 0;
      int successCount = 0;
      final totalCount = pendingSegments.length;

      final queue = GlobalDownloadQueue();
      for (final segment in pendingSegments) {
        queue.enqueue(
          mediaUrl: mediaUrl,
          segment: segment,
          cacheDir: task.cacheDir,
          priority: kPriorityPreload,
          onProgress: (bytes) {
            task.updateSegmentStatus(segment, SegmentStatus.downloading, bytes);
          },
          onComplete: (success) {
            completedCount++;
            if (success) successCount++;
            if (completedCount >= totalCount && !completer.isCompleted) {
              completer.complete(successCount > 0);
            }
          },
        );
      }

      return await completer.future;
    } catch (e) {
      log(() => 'Preload error: $e');
      return false;
    }
  }

  /// 设置当前播放
  static void setCurrentPlaying(String? mediaUrl) {
    GlobalDownloadQueue().setCurrentPlaying(mediaUrl);
  }

  /// 取消媒体下载
  static void cancelMediaDownload(String mediaUrl, {bool cancelActive = true}) {
    GlobalDownloadQueue().cancelMedia(mediaUrl, cancelActive: cancelActive);
  }

  /// 取消所有后台下载
  static void cancelAllBackgroundDownloads() {
    GlobalDownloadQueue().cancelAllExceptCurrent();
  }

  /// 暂停所有下载
  static void pauseAllDownloads() {
    GlobalDownloadQueue().pauseAll();
  }

  /// 获取下载队列状态
  static Map<String, dynamic> getDownloadQueueStats() {
    return GlobalDownloadQueue().getQueueStats();
  }

  /// 获取下载进度
  static Future<double> getDownloadProgress(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final task = await instance._downloadManager.getOrCreateTask(
        mediaUrl,
        headers: headers,
      );
      return task.downloadProgress;
    } catch (e) {
      return 0.0;
    }
  }

  /// 检查是否已完全缓存
  static Future<bool> isFullyCached(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final task = await instance._downloadManager.getOrCreateTask(
        mediaUrl,
        headers: headers,
      );
      return task.isFullyDownloaded;
    } catch (e) {
      return false;
    }
  }

  /// 清理缓存
  static Future<void> cleanupCache({int? maxSize}) async {
    await instance._downloadManager.cleanupCacheLRU(
      maxSize ?? kDefaultMaxCacheSize,
    );
  }

  /// 删除指定媒体缓存
  static Future<bool> removeMediaCache(
    String mediaUrl, {
    Map<String, String>? headers,
  }) async {
    try {
      final manager = instance._downloadManager;
      final headersString = canonicalizeHeaders(headers);
      final taskKey = headersString.isEmpty
          ? mediaUrl
          : '$mediaUrl|$headersString';

      if (manager.tasks.containsKey(taskKey)) {
        final task = manager.tasks[taskKey]!;
        if (task.hasActiveSessions) {
          log(() => 'Cannot remove cache: media is being played');
          return false;
        }

        task.cancel();
        manager.tasks.remove(taskKey);

        if (await task.cacheDir.exists()) {
          await task.cacheDir.delete(recursive: true);
        }

        log(() => 'Media cache removed: $mediaUrl');
        return true;
      }

      final cacheRoot = await manager.getCacheRoot();
      final urlHash = computeMd5Hash(taskKey);
      final cacheDir = Directory(p.join(cacheRoot.path, urlHash));

      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
        log(() => 'Media cache removed: $mediaUrl');
        return true;
      }

      return false;
    } catch (e) {
      log(() => 'Failed to remove cache: $e');
      return false;
    }
  }

  /// 获取缓存统计
  static Future<Map<String, dynamic>> getCacheStats() async {
    try {
      final manager = instance._downloadManager;
      final cacheRoot = await manager.getCacheRoot();

      int totalSize = 0;
      int mediaCount = 0;

      if (await cacheRoot.exists()) {
        await for (final entity in cacheRoot.list()) {
          if (entity is Directory) {
            mediaCount++;
            await for (final file in entity.list()) {
              if (file is File) {
                totalSize += await file.length();
              }
            }
          }
        }
      }

      return {
        'totalSize': totalSize,
        'totalSizeMB': (totalSize / 1024 / 1024).toStringAsFixed(2),
        'mediaCount': mediaCount,
        'maxSize': kDefaultMaxCacheSize,
        'maxSizeMB': (kDefaultMaxCacheSize / 1024 / 1024).toStringAsFixed(0),
        'usagePercent': ((totalSize / kDefaultMaxCacheSize) * 100)
            .toStringAsFixed(1),
      };
    } catch (e) {
      log(() => 'Failed to get cache stats: $e');
      return {
        'totalSize': 0,
        'totalSizeMB': '0',
        'mediaCount': 0,
        'maxSize': kDefaultMaxCacheSize,
        'maxSizeMB': (kDefaultMaxCacheSize / 1024 / 1024).toStringAsFixed(0),
        'usagePercent': '0',
      };
    }
  }
}
