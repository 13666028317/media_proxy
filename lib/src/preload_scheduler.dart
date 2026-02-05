// =============================================================================
// 智能预加载调度器
// =============================================================================

import 'dart:async';

import 'media_cache_proxy.dart';
import 'utils.dart';

/// 预加载任务请求
class PreloadRequest {
  final String url;
  final Map<String, String>? headers;
  final int segmentCount;
  final bool includeMoov;

  PreloadRequest(
    this.url, {
    this.headers,
    this.segmentCount = 1,
    this.includeMoov = true,
  });
}

/// 智能预加载调度器
///
/// 特性：
/// 1. 防抖 (Debounce): 防止快速滑动时触发无效下载
/// 2. 自动取消 (Auto-Cancel): 切换目标时，取消旧的待定任务
/// 3. 串行执行: 避免同时发起过多网络请求抢占带宽
class PreloadScheduler {
  static final PreloadScheduler _instance = PreloadScheduler._internal();
  factory PreloadScheduler() => _instance;
  PreloadScheduler._internal();

  Timer? _debounceTimer;
  final Duration _debounceDuration = const Duration(milliseconds: 300);

  // 当前待处理的任务
  PreloadRequest? _pendingRequest;

  // 正在执行的预加载任务 URL
  String? _executingUrl;

  /// 调度预加载任务
  ///
  /// 调用此方法后，会等待 [debounceDuration] (默认 300ms)。
  /// 如果在此期间再次调用，会取消前一次请求，重新计时。
  ///
  /// [immediate] 如果为 true，则跳过防抖立即执行（适合确定用户已经停下来的场景）
  void schedule(
    String url, {
    Map<String, String>? headers,
    int segmentCount = 1,
    bool includeMoov = true,
    bool immediate = false,
  }) {
    // 如果请求的是当前正在执行的任务，忽略
    if (_executingUrl == url) return;

    // 取消之前的防抖计时
    _debounceTimer?.cancel();

    // 如果有之前的待定任务且 URL 不同，说明用户意图变了，该任务已作废
    if (_pendingRequest != null && _pendingRequest!.url != url) {
      log(() => 'Preload request dropped: ${_pendingRequest!.url}');
    }

    _pendingRequest = PreloadRequest(
      url,
      headers: headers,
      segmentCount: segmentCount,
      includeMoov: includeMoov,
    );

    if (immediate) {
      _executePending();
    } else {
      _debounceTimer = Timer(_debounceDuration, _executePending);
    }
  }

  /// 取消所有待定任务
  void cancelAll() {
    _debounceTimer?.cancel();
    _pendingRequest = null;

    // 如果有正在执行的预加载，也尝试取消它
    if (_executingUrl != null) {
      MediaCacheProxy.cancelMediaDownload(_executingUrl!, cancelActive: true);
      _executingUrl = null;
    }
  }

  /// 执行待定任务
  Future<void> _executePending() async {
    final request = _pendingRequest;
    _pendingRequest = null; // 清空待定

    if (request == null) return;

    // 如果之前的任务还没完，根据策略决定是否取消
    // 这里我们采用"抢占式"策略：新任务优先，取消旧任务的下载
    if (_executingUrl != null && _executingUrl != request.url) {
      log(() => 'Preempting preload: $_executingUrl -> ${request.url}');
      MediaCacheProxy.cancelMediaDownload(_executingUrl!);
    }

    _executingUrl = request.url;
    log(() => 'Starting smart preload: ${request.url}');

    try {
      await MediaCacheProxy.preload(
        request.url,
        headers: request.headers,
        segmentCount: request.segmentCount,
        includeMoov: request.includeMoov,
      );
    } catch (e) {
      log(() => 'Smart preload failed: $e');
    } finally {
      if (_executingUrl == request.url) {
        _executingUrl = null;
      }
    }
  }
}
