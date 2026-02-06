// =============================================================================
// 工具函数
// =============================================================================

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'config.dart';

/// 打印日志（仅在开启日志时打印，使用函数式参数避免不必要的字符串构建）
void log(String Function() messageBuilder) {
  if (MediaProxyConfig.instance.enableLogging) {
    if (kDebugMode) {
      print(
        '[MediaCacheProxy] ${DateTime.now().toIso8601String()} - ${messageBuilder()}',
      );
    }
  }
}

/// 生成唯一的会话ID
String generateSessionId() {
  return '${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(99999)}';
}

/// 计算 MD5 哈希（用于目录名）
String computeMd5Hash(String input) {
  // 使用简单的哈希算法替代 MD5
  // 注意：这不是加密安全的，但用于目录名足够了
  int hash = 0;
  for (int i = 0; i < input.length; i++) {
    hash = ((hash << 5) - hash) + input.codeUnitAt(i);
    hash = hash & 0xFFFFFFFF;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

/// 标准化 Headers 以便进行哈希计算
String canonicalizeHeaders(Map<String, String>? headers) {
  if (headers == null || headers.isEmpty) return '';
  final sortedKeys = headers.keys.toList()..sort();
  return sortedKeys.map((k) => '$k:${headers[k]}').join('|');
}

/// 格式化文件大小
String formatFileSize(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2)} GB';
  } else if (bytes >= 1024 * 1024) {
    return '${(bytes / 1024 / 1024).toStringAsFixed(2)} MB';
  } else if (bytes >= 1024) {
    return '${(bytes / 1024).toStringAsFixed(2)} KB';
  } else {
    return '$bytes B';
  }
}

/// 格式化下载速度
String? formatSpeed(int? bytesPerSecond) {
  if (bytesPerSecond == null) return null;
  if (bytesPerSecond > 1024 * 1024) {
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(2)} MB/s';
  } else if (bytesPerSecond > 1024) {
    return '${(bytesPerSecond / 1024).toStringAsFixed(2)} KB/s';
  } else {
    return '$bytesPerSecond B/s';
  }
}

/// 延迟重试（指数退避）
Future<void> retryWithExponentialBackoff({
  required Future<bool> Function() operation,
  required int maxRetries,
  required int initialDelayMs,
}) async {
  int retryCount = 0;
  int delay = initialDelayMs;

  while (retryCount < maxRetries) {
    try {
      if (await operation()) {
        return;
      }
    } catch (e) {
      log(() => 'Operation failed (attempt ${retryCount + 1}/$maxRetries): $e');
    }

    retryCount++;
    if (retryCount < maxRetries) {
      await Future.delayed(Duration(milliseconds: delay));
      delay *= 2; // 指数退避
    }
  }
}

/// 安全的 HttpClient 关闭
Future<void> closeHttpClientSafely(HttpClient? client) async {
  if (client != null) {
    try {
      client.close(force: true);
    } catch (e) {
      log(() => 'Error closing HttpClient: $e');
    }
  }
}

/// 创建 HttpClient（配置连接池和超时）
HttpClient createHttpClient() {
  final client = HttpClient();
  // 🔑 优化：放宽连接限制，避免死锁
  client.maxConnectionsPerHost = 16;
  client.connectionTimeout = Duration(
    milliseconds: MediaProxyConfig.instance.httpConnectTimeoutMs,
  );
  client.idleTimeout = Duration(
    seconds: MediaProxyConfig.instance.httpIdleTimeoutSeconds,
  );
  return client;
}

/// 等待条件满足或超时
Future<bool> waitForCondition({
  required bool Function() condition,
  required Duration timeout,
  required Duration pollInterval,
}) async {
  final startTime = DateTime.now();

  while (DateTime.now().difference(startTime) < timeout) {
    if (condition()) {
      return true;
    }
    await Future.delayed(pollInterval);
  }

  return false;
}
