// =============================================================================
// Media Proxy - 媒体缓存代理库
// =============================================================================
//
// 使用示例:
// ```dart
// import 'package:your_app/player/Media_proxy/media_proxy.dart';
//
// // 启动代理
// final proxyUrl = await MediaCacheProxy.getProxyUrl('https://example.com/video.mp4');
//
// // 播放视频
// videoPlayer.open(Media(proxyUrl));
// ```
//
// 主要优化:
// 1. 模块化设计 - 代码拆分为多个文件，职责清晰
// 2. HttpClient 复用 - 减少连接创建开销
// 3. 关键状态立即保存 - 避免数据丢失
// 4. MD5 哈希 - 避免 URL 哈希冲突
// 5. 分片数量限制 - 防止内存溢出
// 6. 下载重试机制 - 提高可靠性
// 7. 流式通知 - 减少轮询开销
// =============================================================================

// 策略与调度
export 'cache_strategy.dart';
export 'constants.dart'
    show
        kEnableLogging,
        kDefaultSegmentSize,
        kDefaultMaxCacheSize,
        kGlobalMaxConcurrentDownloads,
        kPriorityPlaying,
        kPriorityPreload,
        kPriorityBackground,
        kPriorityPlayingUrgent;
export 'download_manager.dart';
export 'download_queue.dart';
export 'download_task.dart';
export 'enums.dart';
// 工具
export 'format_helper.dart';
// 核心类
export 'media_cache_proxy.dart';
// 模型
export 'media_segment.dart';
export 'player_session.dart';
export 'preload_scheduler.dart';
// 进度监听
export 'progress_listener.dart';
export 'utils.dart';
