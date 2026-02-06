// =============================================================================
// MediaDownloadTask - 单个媒体的下载任务
// =============================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path/path.dart' as p;

import 'config.dart';
import 'download_queue.dart';
import 'enums.dart';
import 'format_helper.dart';
import 'media_segment.dart';
import 'utils.dart';

/// 单个媒体文件的下载任务
///
/// 负责管理一个媒体URL的所有分片、下载状态和缓存文件
class MediaDownloadTask {
  final String mediaUrl;
  final Directory cacheDir;
  final Map<String, String>? requestHeaders;

  int contentLength = -1;
  String? _contentType;
  final List<MediaSegment> _segments = [];
  int _activeSessionCount = 0;
  bool _isCancelled = false;
  DateTime lastAccessTime = DateTime.now();

  // 配置保存相关
  File get _configFile => File(p.join(cacheDir.path, 'config.json'));
  Timer? _saveConfigTimer;
  bool _configDirty = false;

  // Moov 相关
  bool? _moovAtStart;
  bool _moovPreloaded = false;
  List<int>? _initialData;

  MediaDownloadTask({
    required this.mediaUrl,
    required this.cacheDir,
    this.requestHeaders,
  });

  // Getters
  String get contentType =>
      _contentType ??
      MediaFormatHelper.inferMimeTypeFromUrl(mediaUrl) ??
      MediaProxyConfig.instance.defaultContentType;
  set contentType(String value) =>
      _contentType = MediaFormatHelper.normalizeMimeType(value);
  bool get hasContentType => _contentType != null;
  bool get isMp4Format => MediaFormatHelper.isMp4Format(_contentType);
  bool get isVideoFormat => MediaFormatHelper.isVideoFormat(_contentType);
  bool get isAudioFormat => MediaFormatHelper.isAudioFormat(_contentType);
  bool get needsMoovOptimization =>
      MediaProxyConfig.instance.enableMoovDetection && isMp4Format;
  bool? get moovAtStart => _moovAtStart;
  List<MediaSegment> get segments => List.unmodifiable(_segments);
  bool get isCancelled => _isCancelled;
  bool get hasActiveSessions => _activeSessionCount > 0;

  /// 更新最后访问时间
  void updateAccessTime() {
    lastAccessTime = DateTime.now();
    _markConfigDirty();
  }

  /// 添加活跃会话
  void addSession() {
    _activeSessionCount++;
    log(() => 'Session added for $mediaUrl, active: $_activeSessionCount');
  }

  /// 移除活跃会话
  void removeSession() {
    _activeSessionCount = max(0, _activeSessionCount - 1);
    log(() => 'Session removed for $mediaUrl, active: $_activeSessionCount');
  }

  /// 取消任务
  void cancel() {
    _isCancelled = true;
    log(() => 'Task cancelled for $mediaUrl');
  }

  /// 初始化任务
  Future<void> initialize() async {
    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    await _loadConfig();
    await _scanExistingFiles();

    if (contentLength <= 0) {
      await _fetchMediaInfo();
    }

    if (needsMoovOptimization && _moovAtStart == null) {
      await _detectMoovPosition();
    }

    if (_segments.isEmpty && contentLength > 0) {
      _initializeSegments();
    }

    log(() => 'Task initialized: $mediaUrl');
    log(() => '  Content-Type: $contentType');
    log(
      () => '  Format: ${MediaFormatHelper.getFormatDescription(_contentType)}',
    );
    log(() => '  Content-Length: $contentLength');
    log(() => '  Segments: ${_segments.length}');
    log(() => '  Completed: ${_segments.where((s) => s.isCompleted).length}');
    if (needsMoovOptimization) {
      log(() => '  Moov at start: $_moovAtStart');
    }
  }

  /// 获取媒体信息
  Future<void> _fetchMediaInfo() async {
    try {
      log(() => 'Fetching media info: $mediaUrl');

      final client = createHttpClient();
      final request = await client.headUrl(Uri.parse(mediaUrl));

      // 🔑 注入自定义 Headers
      if (requestHeaders != null && requestHeaders!.isNotEmpty) {
        requestHeaders!.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      final response = await request.close();

      final lengthStr = response.headers.value(HttpHeaders.contentLengthHeader);
      if (lengthStr != null) {
        contentLength = int.tryParse(lengthStr) ?? -1;
      }

      final serverType = response.headers.value(HttpHeaders.contentTypeHeader);
      final resolvedType = MediaFormatHelper.determineMimeType(
        serverContentType: serverType?.split(';').first.trim(),
        url: mediaUrl,
      );
      _contentType = resolvedType;

      final acceptRanges = response.headers.value(
        HttpHeaders.acceptRangesHeader,
      );
      if (acceptRanges != 'bytes') {
        log(() => 'Server may not support Range requests');
      }

      await closeHttpClientSafely(client);
      _markConfigDirty();

      log(() => 'Media info: length=$contentLength, type=$contentType');
    } catch (e) {
      log(() => 'Failed to fetch media info via HEAD: $e');
      await _fetchMediaInfoViaGet();
    }
  }

  /// 使用 GET 请求获取媒体信息
  Future<void> _fetchMediaInfoViaGet() async {
    try {
      log(() => 'Fetching media info via GET: $mediaUrl');

      final client = createHttpClient();
      final request = await client.getUrl(Uri.parse(mediaUrl));

      // 🔑 注入自定义 Headers
      if (requestHeaders != null && requestHeaders!.isNotEmpty) {
        requestHeaders!.forEach((key, value) {
          request.headers.set(key, value);
        });
      }

      request.headers.set(
        HttpHeaders.rangeHeader,
        'bytes=0-${MediaProxyConfig.instance.moovDetectionBytes - 1}',
      );

      final response = await request.close();

      if (response.statusCode == HttpStatus.partialContent) {
        final contentRange = response.headers.value(
          HttpHeaders.contentRangeHeader,
        );
        if (contentRange != null) {
          final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
          if (match != null) {
            contentLength = int.parse(match.group(1)!);
          }
        }
      } else if (response.statusCode == HttpStatus.ok) {
        final lengthStr = response.headers.value(
          HttpHeaders.contentLengthHeader,
        );
        if (lengthStr != null) {
          contentLength = int.tryParse(lengthStr) ?? -1;
        }
      } else {
        await response.drain();
        await closeHttpClientSafely(client);
        throw Exception('HTTP ${response.statusCode}');
      }

      final serverType = response.headers.value(HttpHeaders.contentTypeHeader);
      final resolvedType = MediaFormatHelper.determineMimeType(
        serverContentType: serverType?.split(';').first.trim(),
        url: mediaUrl,
      );
      _contentType = resolvedType;

      final bytes = await response.expand((x) => x).toList();
      _initialData = bytes;

      await closeHttpClientSafely(client);
      _markConfigDirty();

      log(() => 'Media info: length=$contentLength, type=$contentType');
    } catch (e) {
      log(() => 'Failed to fetch media info: $e');
      rethrow;
    }
  }

  /// 检测 MP4 moov 位置
  Future<void> _detectMoovPosition() async {
    if (!isMp4Format) {
      log(() => 'Skipping moov detection: not MP4 format ($contentType)');
      return;
    }

    if (contentLength > 0 &&
        contentLength < MediaProxyConfig.instance.skipMoovDetectionThreshold) {
      log(() => 'Small file ($contentLength bytes), skip moov detection');
      _moovAtStart = true;
      return;
    }

    try {
      log(() => 'Detecting moov atom position for MP4...');

      if (_initialData != null && _initialData!.isNotEmpty) {
        _moovAtStart = _parseMoovPosition(_initialData!);
        log(
          () => 'Moov detection from initial data: moovAtStart=$_moovAtStart',
        );
        _initialData = null;
        return;
      }

      final firstSegment = _segments.isNotEmpty ? _segments.first : null;
      if (firstSegment != null && firstSegment.isCompleted) {
        final file = firstSegment.getSegmentFile(cacheDir);
        if (await file.exists()) {
          final bytes = await file
              .openRead(
                0,
                min(
                  MediaProxyConfig.instance.moovDetectionBytes,
                  firstSegment.expectedSize,
                ),
              )
              .expand((x) => x)
              .toList();
          _moovAtStart = _parseMoovPosition(bytes);
          log(() => 'Moov detection from cache: moovAtStart=$_moovAtStart');
          return;
        }
      }

      // 🔑 优化：彻底移除 moov 探测时的网络请求兜底
      // 原因：这会绕过全局队列控制，导致在首屏加载时抢占带宽，甚至引发死锁。
      // 策略：如果本地没有，直接假设 moov 在末尾 (_moovAtStart = false)，
      // 稍后由 preloadMoovSegment 在合适时机（避开首屏）去下载。
      log(
        () => 'Moov detection: local data insufficient, assuming moov at end.',
      );
      _moovAtStart = false;

      /* 移除旧的危险网络请求代码
      final client = createHttpClient();
      final request = await client.getUrl(Uri.parse(mediaUrl));
      request.headers
          .set(HttpHeaders.rangeHeader, 'bytes=0-${kMoovDetectionBytes - 1}');
      final response = await request.close();

      if (response.statusCode == HttpStatus.partialContent ||
          response.statusCode == HttpStatus.ok) {
        final bytes = await response.expand((x) => x).toList();
        _moovAtStart = _parseMoovPosition(bytes);
        log(() => 'Moov detection from network: moovAtStart=$_moovAtStart');
      }

      await closeHttpClientSafely(client);
      */
    } catch (e) {
      log(() => 'Moov detection failed: $e');
      _moovAtStart = false;
    }
  }

  /// 解析 moov 位置
  bool _parseMoovPosition(List<int> data) {
    if (data.length < 8) return false;

    int offset = 0;

    while (offset + 8 <= data.length) {
      final size =
          (data[offset] << 24) |
          (data[offset + 1] << 16) |
          (data[offset + 2] << 8) |
          data[offset + 3];

      final type = String.fromCharCodes(data.sublist(offset + 4, offset + 8));

      log(() => '   Found atom: $type, size: $size at offset $offset');

      if (type == 'moov') {
        return true;
      } else if (type == 'mdat') {
        return false;
      }

      if (size <= 0) break;
      offset += size;
    }

    return false;
  }

  /// 预加载 moov 分片
  Future<void> preloadMoovSegment() async {
    if (!isMp4Format || _moovPreloaded || _moovAtStart == true) return;
    if (_segments.isEmpty || contentLength <= 0) return;

    final lastSegment = _segments.last;
    // 已完成或正在下载，无需再入队
    if (lastSegment.isCompleted || lastSegment.isDownloading) {
      _moovPreloaded = true;
      return;
    }

    log(() => 'Preloading moov segment: $lastSegment');
    _moovPreloaded = true; // 标记已入队，避免重复入队

    // 提交到下载队列，使用较高优先级确保 moov 快速下载
    GlobalDownloadQueue().enqueue(
      mediaUrl: mediaUrl,
      segment: lastSegment,
      cacheDir: cacheDir,
      headers: requestHeaders,
      priority:
          MediaProxyConfig.instance.priorityPlayingUrgent - 50, // 150，仅次于首帧分片
      onProgress: (bytes) {
        updateSegmentStatus(lastSegment, SegmentStatus.downloading, bytes);
      },
      onComplete: (success) {
        if (success) {
          updateSegmentStatus(lastSegment, SegmentStatus.completed);
        } else {
          _moovPreloaded = false; // 失败则允许重试
        }
      },
    );
  }

  /// 加载配置
  Future<void> _loadConfig() async {
    try {
      log(() => 'Loading config from: ${_configFile.path}');

      if (await _configFile.exists()) {
        final content = await _configFile.readAsString();

        if (content.isNotEmpty) {
          final json = jsonDecode(content) as Map<String, dynamic>;

          contentLength = json['contentLength'] as int? ?? -1;
          final savedType = json['contentType'] as String?;
          if (savedType != null && savedType.isNotEmpty) {
            _contentType = savedType;
          }

          final lastAccessMs = json['lastAccessTime'] as int?;
          if (lastAccessMs != null) {
            lastAccessTime = DateTime.fromMillisecondsSinceEpoch(lastAccessMs);
          }

          final headersJson = json['requestHeaders'] as Map<dynamic, dynamic>?;
          if (headersJson != null) {
            // 已在构造函数中通过参数传入，这里仅在需要从持久化恢复且构造函数没传时有用
            // 但通常构造函数传入的优先级更高（即最新的请求头）
          }

          final segmentsJson = json['segments'] as List<dynamic>?;
          if (segmentsJson != null) {
            _segments.clear();
            for (final segJson in segmentsJson) {
              final seg = MediaSegment.fromJson(
                segJson as Map<String, dynamic>,
              );
              _segments.add(seg);
            }
            _segments.sort((a, b) => a.startByte.compareTo(b.startByte));

            final completed = _segments.where((s) => s.isCompleted).length;
            final pending = _segments
                .where((s) => s.status == SegmentStatus.pending)
                .length;
            log(
              () =>
                  'Config loaded: ${_segments.length} segments (completed: $completed, pending: $pending)',
            );
          }
        }
      }
    } catch (e, st) {
      log(() => 'Failed to load config: $e\n$st');
    }
  }

  /// 标记配置需要保存（防抖）
  void _markConfigDirty() {
    _configDirty = true;

    _saveConfigTimer?.cancel();
    _saveConfigTimer = Timer(
      Duration(milliseconds: MediaProxyConfig.instance.configSaveIntervalMs),
      _saveConfigNow,
    );
  }

  /// 立即保存配置
  Future<void> _saveConfigNow() async {
    if (!_configDirty) return;

    try {
      final json = {
        'contentLength': contentLength,
        'contentType': contentType,
        'lastAccessTime': lastAccessTime.millisecondsSinceEpoch,
        'requestHeaders': requestHeaders,
        'segments': _segments.map((s) => s.toJson()).toList(),
      };
      await _configFile.writeAsString(jsonEncode(json));
      _configDirty = false;
      log(() => 'Config saved');
    } catch (e) {
      log(() => 'Failed to save config: $e');
    }
  }

  /// 强制保存配置
  Future<void> forceFlushConfig() async {
    _saveConfigTimer?.cancel();
    _configDirty = true;
    await _saveConfigNow();
  }

  /// 扫描已有文件
  Future<void> _scanExistingFiles() async {
    try {
      final entities = await cacheDir.list().toList();
      int foundSegments = 0;

      for (final entity in entities) {
        if (entity is! File) continue;

        final fileName = p.basename(entity.path);
        if (fileName.endsWith('.json') || fileName.endsWith('.tmp')) continue;
        if (!fileName.endsWith('.seg')) continue;

        final parts = fileName.replaceAll('.seg', '').split('_');
        if (parts.length != 2) continue;

        final start = int.tryParse(parts[0]);
        final end = int.tryParse(parts[1]);
        if (start == null || end == null) continue;

        final fileSize = await entity.length();
        final expectedSize = end - start + 1;

        var segment = _segments.firstWhere(
          (s) => s.startByte == start && s.endByte == end,
          orElse: () {
            final newSeg = MediaSegment(startByte: start, endByte: end);
            _segments.add(newSeg);
            return newSeg;
          },
        );

        if (fileSize >= expectedSize) {
          segment.status = SegmentStatus.completed;
          segment.downloadedBytes = fileSize;
          foundSegments++;
        } else if (fileSize > 0) {
          segment.status = SegmentStatus.pending;
          segment.downloadedBytes = fileSize;
        }
      }

      log(() => 'Scan completed: found $foundSegments completed segments');
      _segments.sort((a, b) => a.startByte.compareTo(b.startByte));
    } catch (e) {
      log(() => 'Failed to scan files: $e');
    }
  }

  /// 初始化分片列表
  void _initializeSegments() {
    _segments.clear();

    // 检查分片数量限制
    final estimatedSegments =
        (contentLength / MediaProxyConfig.instance.segmentSize).ceil();
    if (estimatedSegments > MediaProxyConfig.instance.maxSegmentCount) {
      log(
        () =>
            'Warning: Estimated segment count ($estimatedSegments) exceeds limit (${MediaProxyConfig.instance.maxSegmentCount})',
      );
    }

    int offset = 0;
    int segmentCount = 0;
    while (offset < contentLength &&
        segmentCount < MediaProxyConfig.instance.maxSegmentCount) {
      final end = min(
        offset + MediaProxyConfig.instance.segmentSize - 1,
        contentLength - 1,
      );
      _segments.add(MediaSegment(startByte: offset, endByte: end));
      offset = end + 1;
      segmentCount++;
    }

    log(() => 'Initialized ${_segments.length} segments');
    _markConfigDirty();
  }

  /// 获取指定范围的分片
  List<MediaSegment> getSegmentsForRange(int rangeStart, int rangeEnd) {
    final result = <MediaSegment>[];

    for (final segment in _segments) {
      if (segment.endByte >= rangeStart && segment.startByte <= rangeEnd) {
        result.add(segment);
      }
    }

    if (result.isEmpty && contentLength > 0) {
      int offset =
          (rangeStart ~/ MediaProxyConfig.instance.segmentSize) *
          MediaProxyConfig.instance.segmentSize;
      while (offset <= rangeEnd && offset < contentLength) {
        final end = min(
          offset + MediaProxyConfig.instance.segmentSize - 1,
          contentLength - 1,
        );

        var existing = _segments.firstWhere(
          (s) => s.startByte == offset,
          orElse: () {
            final newSeg = MediaSegment(startByte: offset, endByte: end);
            _segments.add(newSeg);
            _segments.sort((a, b) => a.startByte.compareTo(b.startByte));
            return newSeg;
          },
        );

        if (existing.endByte >= rangeStart && existing.startByte <= rangeEnd) {
          result.add(existing);
        }

        offset = end + 1;
      }

      _markConfigDirty();
    }

    return result;
  }

  /// 更新分片状态（关键状态立即保存）
  void updateSegmentStatus(
    MediaSegment segment,
    SegmentStatus status, [
    int? downloadedBytes,
  ]) {
    segment.updateStatus(status);
    if (downloadedBytes != null) {
      segment.downloadedBytes = downloadedBytes;
    }

    // 关键状态立即保存
    if (status == SegmentStatus.completed || status == SegmentStatus.failed) {
      forceFlushConfig();
    } else {
      _markConfigDirty();
    }
  }

  /// 获取下载进度
  double get downloadProgress {
    if (_segments.isEmpty || contentLength <= 0) return 0.0;

    int downloadedBytes = 0;
    for (final segment in _segments) {
      if (segment.isCompleted) {
        downloadedBytes += segment.expectedSize;
      } else {
        downloadedBytes += segment.downloadedBytes;
      }
    }

    return downloadedBytes / contentLength;
  }

  /// 是否已完全下载
  bool get isFullyDownloaded =>
      _segments.isNotEmpty && _segments.every((s) => s.isCompleted);

  /// 释放资源
  void dispose() {
    _saveConfigTimer?.cancel();
    for (final segment in _segments) {
      segment.dispose();
    }
    log(() => 'Task disposed: $mediaUrl');
  }
}
