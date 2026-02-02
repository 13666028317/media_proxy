// =============================================================================
// 常量配置 - 所有可配置参数集中管理
// =============================================================================

/// 默认分片大小: 2MB
const int kDefaultSegmentSize = 2 * 1024 * 1024;

/// 最大并行下载数量
const int kMaxConcurrentDownloads = 3;

/// 流式输出时的轮询间隔（毫秒）
const int kStreamPollIntervalMs = 100;

/// 配置文件自动保存间隔（毫秒）
const int kConfigSaveIntervalMs = 1000;

/// 日志开关
const bool kEnableLogging = true;

/// 是否启用 moov atom 智能检测和预加载
const bool kEnableMoovDetection = true;

/// moov 检测时读取的字节数
const int kMoovDetectionBytes = 64;

/// 预下载末尾的字节数（用于加载 moov atom）
const int kMoovPreloadBytes = kDefaultSegmentSize;

/// 默认最大缓存大小: 500MB
const int kDefaultMaxCacheSize = 500 * 1024 * 1024;

/// 缓存清理的目标大小比例
const double kCacheCleanupRatio = 0.7;

/// 是否启用自动缓存清理
const bool kEnableAutoCacheCleanup = true;

/// 跳过 moov 检测的文件大小阈值
const int kSkipMoovDetectionThreshold = 5 * 1024 * 1024;

/// 是否总是预加载末尾分片
const bool kAlwaysPreloadEndSegment = true;

/// 默认的 Content-Type
const String kDefaultContentType = 'application/octet-stream';

/// 全局最大并发下载数
const int kGlobalMaxConcurrentDownloads = 4;

/// 单个媒体文件的最大并发下载数
const int kPerMediaMaxConcurrentDownloads = 3;

/// 当前播放媒体的下载优先级 (普通分片)
const int kPriorityPlaying = 100;

/// 当前播放媒体的**紧急**下载优先级 (当前播放位置的分片)
const int kPriorityPlayingUrgent = 200;

/// 预加载媒体的下载优先级
const int kPriorityPreload = 50;

/// 后台下载的默认优先级
const int kPriorityBackground = 10;

/// 是否在用户切换媒体时暂停旧媒体的下载
const bool kPauseOldDownloadsOnSwitch = true;

/// 非活跃任务的下载超时时间（毫秒）
const int kInactiveTaskTimeoutMs = 5000;

/// 最大分片数量限制（防止内存溢出）
const int kMaxSegmentCount = 5000;

/// 下载重试次数
const int kDownloadRetryCount = 3;

/// 下载重试初始延迟（毫秒）
const int kDownloadRetryInitialDelayMs = 1000;

/// HttpClient 连接超时（毫秒）
const int kHttpConnectTimeoutMs = 10000;

/// HttpClient 响应超时（毫秒）
const int kHttpResponseTimeoutMs = 15000;

/// HttpClient 空闲连接超时（秒）
const int kHttpIdleTimeoutSeconds = 30;

/// MP4 相关的 MIME 类型
const Set<String> kMp4MimeTypes = {
  'video/mp4',
  'video/x-m4v',
  'video/quicktime',
  'audio/mp4',
  'audio/x-m4a',
  'audio/m4a',
};

/// 媒体 MIME 类型
const Set<String> kVideoMimeTypes = {
  'video/mp4',
  'video/x-m4v',
  'video/quicktime',
  'video/webm',
  'video/x-matroska',
  'video/x-msvideo',
  'video/x-flv',
  'video/mp2t',
  'video/3gpp',
  'video/3gpp2',
};

/// 音频 MIME 类型
const Set<String> kAudioMimeTypes = {
  'audio/mpeg',
  'audio/mp3',
  'audio/aac',
  'audio/x-aac',
  'audio/mp4',
  'audio/x-m4a',
  'audio/m4a',
  'audio/flac',
  'audio/x-flac',
  'audio/wav',
  'audio/x-wav',
  'audio/ogg',
  'audio/opus',
  'audio/x-ms-wma',
  'audio/webm',
};

/// 文件扩展名到 MIME 类型的映射
const Map<String, String> kExtensionToMimeType = {
  '.mp4': 'video/mp4',
  '.m4v': 'video/x-m4v',
  '.mov': 'video/quicktime',
  '.mkv': 'video/x-matroska',
  '.webm': 'video/webm',
  '.avi': 'video/x-msvideo',
  '.flv': 'video/x-flv',
  '.ts': 'video/mp2t',
  '.3gp': 'video/3gpp',
  '.3g2': 'video/3gpp2',
  '.mp3': 'audio/mpeg',
  '.aac': 'audio/aac',
  '.m4a': 'audio/x-m4a',
  '.flac': 'audio/flac',
  '.wav': 'audio/wav',
  '.ogg': 'audio/ogg',
  '.opus': 'audio/opus',
  '.wma': 'audio/x-ms-wma',
};
