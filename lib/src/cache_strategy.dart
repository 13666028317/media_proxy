// =============================================================================
// 缓存策略增强模块
// =============================================================================

import 'dart:io';

import 'config.dart';
import 'utils.dart';

/// 缓存清理策略接口
abstract class CacheEvictionPolicy {
  /// 检查是否需要清理
  /// [currentSize] 当前缓存总大小
  /// [cacheFiles] 所有缓存项列表（已排序）
  /// 返回需要删除的缓存项列表
  List<CacheEntry> selectFilesToEvict(
    int currentSize,
    List<CacheEntry> cacheFiles,
  );
}

/// 缓存项元数据
class CacheEntry {
  final Directory directory;
  final int sizeBytes;
  final DateTime lastAccessTime;
  final String mediaUrl;

  CacheEntry({
    required this.directory,
    required this.sizeBytes,
    required this.lastAccessTime,
    required this.mediaUrl,
  });
}

/// 组合策略：TTL (过期时间) + LRU (最近最少使用)
class SmartCachePolicy implements CacheEvictionPolicy {
  /// 缓存最大存活时间（默认 7 天）
  final Duration maxAge;

  /// 最大缓存大小限制
  final int maxSizeBytes;

  SmartCachePolicy({this.maxAge = const Duration(days: 7), int? maxSizeBytes})
    : maxSizeBytes = maxSizeBytes ?? MediaProxyConfig.instance.maxCacheSize;

  @override
  List<CacheEntry> selectFilesToEvict(
    int currentSize,
    List<CacheEntry> cacheFiles,
  ) {
    final toDelete = <CacheEntry>[];
    final now = DateTime.now();
    int sizeAfterTTL = currentSize;

    // 1. TTL 检查：优先删除过期的文件
    for (final entry in cacheFiles) {
      if (now.difference(entry.lastAccessTime) > maxAge) {
        toDelete.add(entry);
        sizeAfterTTL -= entry.sizeBytes;
        log(
          () =>
              'TTL Eviction: ${entry.mediaUrl} (Age: ${now.difference(entry.lastAccessTime).inHours}h)',
        );
      }
    }

    // 如果清理过期文件后，空间依然不够，则执行 LRU
    if (sizeAfterTTL > maxSizeBytes) {
      // 确保按时间排序（最久未访问的在前）
      // 注意：传入的 list 应该已经是排好序的，但为了保险这里可以 copy 一份过滤后的
      final remaining = cacheFiles.where((e) => !toDelete.contains(e)).toList()
        ..sort((a, b) => a.lastAccessTime.compareTo(b.lastAccessTime));

      for (final entry in remaining) {
        if (sizeAfterTTL <=
            maxSizeBytes * MediaProxyConfig.instance.cacheCleanupRatio)
          break; // 降到 70% 水位停止

        toDelete.add(entry);
        sizeAfterTTL -= entry.sizeBytes;
        log(() => 'LRU Eviction: ${entry.mediaUrl}');
      }
    }

    return toDelete;
  }
}
