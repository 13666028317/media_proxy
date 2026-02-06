// =============================================================================
// MediaProxyConfig - 可配置参数管理
// =============================================================================

import 'constants.dart';

/// 媒体代理配置类
///
/// 使用示例:
/// ```dart
/// // 在应用启动时初始化配置
/// MediaProxyConfig.init(
///   segmentSize: 4 * 1024 * 1024, // 4MB
///   maxCacheSize: 1024 * 1024 * 1024, // 1GB
///   enableLogging: false,
/// );
///
/// // 之后通过 instance 访问配置
/// final size = MediaProxyConfig.instance.segmentSize;
/// ```
class MediaProxyConfig {
  static MediaProxyConfig? _instance;

  /// 获取配置实例（如果未初始化则使用默认值）
  static MediaProxyConfig get instance {
    _instance ??= MediaProxyConfig._();
    return _instance!;
  }

  /// 初始化配置（应在应用启动时调用一次）
  ///
  /// 注意：此方法应在使用 MediaCacheProxy 之前调用
  static void init({
    // ===== 分片配置 =====
    int? segmentSize,
    int? maxSegmentCount,

    // ===== 并发配置 =====
    int? maxConcurrentDownloads,
    int? globalMaxConcurrentDownloads,
    int? perMediaMaxConcurrentDownloads,

    // ===== 缓存配置 =====
    int? maxCacheSize,
    double? cacheCleanupRatio,
    bool? enableAutoCacheCleanup,

    // ===== 日志配置 =====
    bool? enableLogging,

    // ===== Moov 优化配置 =====
    bool? enableMoovDetection,
    int? moovDetectionBytes,
    int? moovPreloadBytes,
    int? skipMoovDetectionThreshold,
    bool? alwaysPreloadEndSegment,

    // ===== 轮询与超时配置 =====
    int? streamPollIntervalMs,
    int? configSaveIntervalMs,
    int? inactiveTaskTimeoutMs,

    // ===== 优先级配置 =====
    int? priorityPlaying,
    int? priorityPlayingUrgent,
    int? priorityPreload,
    int? priorityBackground,

    // ===== 下载行为配置 =====
    bool? pauseOldDownloadsOnSwitch,
    int? downloadRetryCount,
    int? downloadRetryInitialDelayMs,

    // ===== HTTP 配置 =====
    int? httpConnectTimeoutMs,
    int? httpResponseTimeoutMs,
    int? httpIdleTimeoutSeconds,
    int? httpStreamReadTimeoutSeconds,

    // ===== 默认值配置 =====
    String? defaultContentType,
  }) {
    _instance = MediaProxyConfig._(
      segmentSize: segmentSize,
      maxSegmentCount: maxSegmentCount,
      maxConcurrentDownloads: maxConcurrentDownloads,
      globalMaxConcurrentDownloads: globalMaxConcurrentDownloads,
      perMediaMaxConcurrentDownloads: perMediaMaxConcurrentDownloads,
      maxCacheSize: maxCacheSize,
      cacheCleanupRatio: cacheCleanupRatio,
      enableAutoCacheCleanup: enableAutoCacheCleanup,
      enableLogging: enableLogging,
      enableMoovDetection: enableMoovDetection,
      moovDetectionBytes: moovDetectionBytes,
      moovPreloadBytes: moovPreloadBytes,
      skipMoovDetectionThreshold: skipMoovDetectionThreshold,
      alwaysPreloadEndSegment: alwaysPreloadEndSegment,
      streamPollIntervalMs: streamPollIntervalMs,
      configSaveIntervalMs: configSaveIntervalMs,
      inactiveTaskTimeoutMs: inactiveTaskTimeoutMs,
      priorityPlaying: priorityPlaying,
      priorityPlayingUrgent: priorityPlayingUrgent,
      priorityPreload: priorityPreload,
      priorityBackground: priorityBackground,
      pauseOldDownloadsOnSwitch: pauseOldDownloadsOnSwitch,
      downloadRetryCount: downloadRetryCount,
      downloadRetryInitialDelayMs: downloadRetryInitialDelayMs,
      httpConnectTimeoutMs: httpConnectTimeoutMs,
      httpResponseTimeoutMs: httpResponseTimeoutMs,
      httpIdleTimeoutSeconds: httpIdleTimeoutSeconds,
      httpStreamReadTimeoutSeconds: httpStreamReadTimeoutSeconds,
      defaultContentType: defaultContentType,
    );
  }

  /// 重置配置为默认值
  static void reset() {
    _instance = null;
  }

  /// 使用当前配置创建新实例（用于部分更新）
  static void update({
    int? segmentSize,
    int? maxSegmentCount,
    int? maxConcurrentDownloads,
    int? globalMaxConcurrentDownloads,
    int? perMediaMaxConcurrentDownloads,
    int? maxCacheSize,
    double? cacheCleanupRatio,
    bool? enableAutoCacheCleanup,
    bool? enableLogging,
    bool? enableMoovDetection,
    int? moovDetectionBytes,
    int? moovPreloadBytes,
    int? skipMoovDetectionThreshold,
    bool? alwaysPreloadEndSegment,
    int? streamPollIntervalMs,
    int? configSaveIntervalMs,
    int? inactiveTaskTimeoutMs,
    int? priorityPlaying,
    int? priorityPlayingUrgent,
    int? priorityPreload,
    int? priorityBackground,
    bool? pauseOldDownloadsOnSwitch,
    int? downloadRetryCount,
    int? downloadRetryInitialDelayMs,
    int? httpConnectTimeoutMs,
    int? httpResponseTimeoutMs,
    int? httpIdleTimeoutSeconds,
    int? httpStreamReadTimeoutSeconds,
    String? defaultContentType,
  }) {
    final current = instance;
    _instance = MediaProxyConfig._(
      segmentSize: segmentSize ?? current.segmentSize,
      maxSegmentCount: maxSegmentCount ?? current.maxSegmentCount,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? current.maxConcurrentDownloads,
      globalMaxConcurrentDownloads:
          globalMaxConcurrentDownloads ?? current.globalMaxConcurrentDownloads,
      perMediaMaxConcurrentDownloads:
          perMediaMaxConcurrentDownloads ??
          current.perMediaMaxConcurrentDownloads,
      maxCacheSize: maxCacheSize ?? current.maxCacheSize,
      cacheCleanupRatio: cacheCleanupRatio ?? current.cacheCleanupRatio,
      enableAutoCacheCleanup:
          enableAutoCacheCleanup ?? current.enableAutoCacheCleanup,
      enableLogging: enableLogging ?? current.enableLogging,
      enableMoovDetection: enableMoovDetection ?? current.enableMoovDetection,
      moovDetectionBytes: moovDetectionBytes ?? current.moovDetectionBytes,
      moovPreloadBytes: moovPreloadBytes ?? current.moovPreloadBytes,
      skipMoovDetectionThreshold:
          skipMoovDetectionThreshold ?? current.skipMoovDetectionThreshold,
      alwaysPreloadEndSegment:
          alwaysPreloadEndSegment ?? current.alwaysPreloadEndSegment,
      streamPollIntervalMs:
          streamPollIntervalMs ?? current.streamPollIntervalMs,
      configSaveIntervalMs:
          configSaveIntervalMs ?? current.configSaveIntervalMs,
      inactiveTaskTimeoutMs:
          inactiveTaskTimeoutMs ?? current.inactiveTaskTimeoutMs,
      priorityPlaying: priorityPlaying ?? current.priorityPlaying,
      priorityPlayingUrgent:
          priorityPlayingUrgent ?? current.priorityPlayingUrgent,
      priorityPreload: priorityPreload ?? current.priorityPreload,
      priorityBackground: priorityBackground ?? current.priorityBackground,
      pauseOldDownloadsOnSwitch:
          pauseOldDownloadsOnSwitch ?? current.pauseOldDownloadsOnSwitch,
      downloadRetryCount: downloadRetryCount ?? current.downloadRetryCount,
      downloadRetryInitialDelayMs:
          downloadRetryInitialDelayMs ?? current.downloadRetryInitialDelayMs,
      httpConnectTimeoutMs:
          httpConnectTimeoutMs ?? current.httpConnectTimeoutMs,
      httpResponseTimeoutMs:
          httpResponseTimeoutMs ?? current.httpResponseTimeoutMs,
      httpIdleTimeoutSeconds:
          httpIdleTimeoutSeconds ?? current.httpIdleTimeoutSeconds,
      httpStreamReadTimeoutSeconds:
          httpStreamReadTimeoutSeconds ?? current.httpStreamReadTimeoutSeconds,
      defaultContentType: defaultContentType ?? current.defaultContentType,
    );
  }

  // ===== 私有构造函数 =====
  MediaProxyConfig._({
    int? segmentSize,
    int? maxSegmentCount,
    int? maxConcurrentDownloads,
    int? globalMaxConcurrentDownloads,
    int? perMediaMaxConcurrentDownloads,
    int? maxCacheSize,
    double? cacheCleanupRatio,
    bool? enableAutoCacheCleanup,
    bool? enableLogging,
    bool? enableMoovDetection,
    int? moovDetectionBytes,
    int? moovPreloadBytes,
    int? skipMoovDetectionThreshold,
    bool? alwaysPreloadEndSegment,
    int? streamPollIntervalMs,
    int? configSaveIntervalMs,
    int? inactiveTaskTimeoutMs,
    int? priorityPlaying,
    int? priorityPlayingUrgent,
    int? priorityPreload,
    int? priorityBackground,
    bool? pauseOldDownloadsOnSwitch,
    int? downloadRetryCount,
    int? downloadRetryInitialDelayMs,
    int? httpConnectTimeoutMs,
    int? httpResponseTimeoutMs,
    int? httpIdleTimeoutSeconds,
    int? httpStreamReadTimeoutSeconds,
    String? defaultContentType,
  }) : segmentSize = segmentSize ?? kDefaultSegmentSize,
       maxSegmentCount = maxSegmentCount ?? kMaxSegmentCount,
       maxConcurrentDownloads =
           maxConcurrentDownloads ?? kMaxConcurrentDownloads,
       globalMaxConcurrentDownloads =
           globalMaxConcurrentDownloads ?? kGlobalMaxConcurrentDownloads,
       perMediaMaxConcurrentDownloads =
           perMediaMaxConcurrentDownloads ?? kPerMediaMaxConcurrentDownloads,
       maxCacheSize = maxCacheSize ?? kDefaultMaxCacheSize,
       cacheCleanupRatio = cacheCleanupRatio ?? kCacheCleanupRatio,
       enableAutoCacheCleanup =
           enableAutoCacheCleanup ?? kEnableAutoCacheCleanup,
       enableLogging = enableLogging ?? kEnableLogging,
       enableMoovDetection = enableMoovDetection ?? kEnableMoovDetection,
       moovDetectionBytes = moovDetectionBytes ?? kMoovDetectionBytes,
       moovPreloadBytes = moovPreloadBytes ?? kMoovPreloadBytes,
       skipMoovDetectionThreshold =
           skipMoovDetectionThreshold ?? kSkipMoovDetectionThreshold,
       alwaysPreloadEndSegment =
           alwaysPreloadEndSegment ?? kAlwaysPreloadEndSegment,
       streamPollIntervalMs = streamPollIntervalMs ?? kStreamPollIntervalMs,
       configSaveIntervalMs = configSaveIntervalMs ?? kConfigSaveIntervalMs,
       inactiveTaskTimeoutMs = inactiveTaskTimeoutMs ?? kInactiveTaskTimeoutMs,
       priorityPlaying = priorityPlaying ?? kPriorityPlaying,
       priorityPlayingUrgent = priorityPlayingUrgent ?? kPriorityPlayingUrgent,
       priorityPreload = priorityPreload ?? kPriorityPreload,
       priorityBackground = priorityBackground ?? kPriorityBackground,
       pauseOldDownloadsOnSwitch =
           pauseOldDownloadsOnSwitch ?? kPauseOldDownloadsOnSwitch,
       downloadRetryCount = downloadRetryCount ?? kDownloadRetryCount,
       downloadRetryInitialDelayMs =
           downloadRetryInitialDelayMs ?? kDownloadRetryInitialDelayMs,
       httpConnectTimeoutMs = httpConnectTimeoutMs ?? kHttpConnectTimeoutMs,
       httpResponseTimeoutMs = httpResponseTimeoutMs ?? kHttpResponseTimeoutMs,
       httpIdleTimeoutSeconds =
           httpIdleTimeoutSeconds ?? kHttpIdleTimeoutSeconds,
       httpStreamReadTimeoutSeconds =
           httpStreamReadTimeoutSeconds ?? kHttpStreamReadTimeoutSeconds,
       defaultContentType = defaultContentType ?? kDefaultContentType;

  // ===== 分片配置 =====

  /// 分片大小（字节）
  final int segmentSize;

  /// 最大分片数量限制（防止内存溢出）
  final int maxSegmentCount;

  // ===== 并发配置 =====

  /// 最大并行下载数量
  final int maxConcurrentDownloads;

  /// 全局最大并发下载数
  final int globalMaxConcurrentDownloads;

  /// 单个媒体文件的最大并发下载数
  final int perMediaMaxConcurrentDownloads;

  // ===== 缓存配置 =====

  /// 最大缓存大小（字节）
  final int maxCacheSize;

  /// 缓存清理的目标大小比例
  final double cacheCleanupRatio;

  /// 是否启用自动缓存清理
  final bool enableAutoCacheCleanup;

  // ===== 日志配置 =====

  /// 是否启用日志
  final bool enableLogging;

  // ===== Moov 优化配置 =====

  /// 是否启用 moov atom 智能检测和预加载
  final bool enableMoovDetection;

  /// moov 检测时读取的字节数
  final int moovDetectionBytes;

  /// 预下载末尾的字节数（用于加载 moov atom）
  final int moovPreloadBytes;

  /// 跳过 moov 检测的文件大小阈值
  final int skipMoovDetectionThreshold;

  /// 是否总是预加载末尾分片
  final bool alwaysPreloadEndSegment;

  // ===== 轮询与超时配置 =====

  /// 流式输出时的轮询间隔（毫秒）
  final int streamPollIntervalMs;

  /// 配置文件自动保存间隔（毫秒）
  final int configSaveIntervalMs;

  /// 非活跃任务的下载超时时间（毫秒）
  final int inactiveTaskTimeoutMs;

  // ===== 优先级配置 =====

  /// 当前播放媒体的下载优先级（普通分片）
  final int priorityPlaying;

  /// 当前播放媒体的紧急下载优先级（当前播放位置的分片）
  final int priorityPlayingUrgent;

  /// 预加载媒体的下载优先级
  final int priorityPreload;

  /// 后台下载的默认优先级
  final int priorityBackground;

  // ===== 下载行为配置 =====

  /// 是否在用户切换媒体时暂停旧媒体的下载
  final bool pauseOldDownloadsOnSwitch;

  /// 下载重试次数
  final int downloadRetryCount;

  /// 下载重试初始延迟（毫秒）
  final int downloadRetryInitialDelayMs;

  // ===== HTTP 配置 =====

  /// HttpClient 连接超时（毫秒）
  final int httpConnectTimeoutMs;

  /// HttpClient 响应超时（毫秒）
  final int httpResponseTimeoutMs;

  /// HttpClient 空闲连接超时（秒）
  final int httpIdleTimeoutSeconds;

  /// 响应流读超时（秒）
  final int httpStreamReadTimeoutSeconds;

  // ===== 默认值配置 =====

  /// 默认的 Content-Type
  final String defaultContentType;

  @override
  String toString() {
    return 'MediaProxyConfig('
        'segmentSize: $segmentSize, '
        'maxCacheSize: $maxCacheSize, '
        'enableLogging: $enableLogging, '
        'globalMaxConcurrentDownloads: $globalMaxConcurrentDownloads'
        ')';
  }
}
