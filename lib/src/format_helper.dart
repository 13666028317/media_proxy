// =============================================================================
// 媒体格式辅助类
// =============================================================================

import 'config.dart';
import 'constants.dart';
import 'utils.dart';

/// 媒体格式辅助类
///
/// 提供格式检测、MIME 类型推断等功能
class MediaFormatHelper {
  /// 从 URL 推断 MIME 类型
  static String? inferMimeTypeFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      String path = uri.path.toLowerCase();

      if (path.isEmpty || path == '/') {
        final lastSlash = url.lastIndexOf('/');
        if (lastSlash != -1) {
          path = url.substring(lastSlash).toLowerCase();
          final queryStart = path.indexOf('?');
          if (queryStart != -1) {
            path = path.substring(0, queryStart);
          }
        }
      }

      for (final entry in kExtensionToMimeType.entries) {
        if (path.endsWith(entry.key)) {
          return entry.value;
        }
      }

      return null;
    } catch (e) {
      log(() => 'Failed to infer MIME type from URL: $e');
      return null;
    }
  }

  /// 判断是否是 MP4 格式
  static bool isMp4Format(String? mimeType) {
    if (mimeType == null) return false;
    final normalized = mimeType.toLowerCase().trim();
    return kMp4MimeTypes.contains(normalized);
  }

  /// 判断是否是视频格式
  static bool isVideoFormat(String? mimeType) {
    if (mimeType == null) return false;
    final normalized = mimeType.toLowerCase().trim();
    return normalized.startsWith('video/') ||
        kVideoMimeTypes.contains(normalized);
  }

  /// 判断是否是音频格式
  static bool isAudioFormat(String? mimeType) {
    if (mimeType == null) return false;
    final normalized = mimeType.toLowerCase().trim();
    return normalized.startsWith('audio/') ||
        kAudioMimeTypes.contains(normalized);
  }

  /// 判断是否是已知的媒体格式
  static bool isKnownMediaFormat(String? mimeType) {
    return isVideoFormat(mimeType) || isAudioFormat(mimeType);
  }

  /// 获取格式描述
  static String getFormatDescription(String? mimeType) {
    if (mimeType == null) return 'unknown';
    if (isMp4Format(mimeType)) return 'MP4-family';
    if (isVideoFormat(mimeType)) return 'video';
    if (isAudioFormat(mimeType)) return 'audio';
    return 'binary';
  }

  /// 规范化 MIME 类型
  static String normalizeMimeType(String mimeType) {
    final normalized = mimeType.toLowerCase().trim();

    switch (normalized) {
      case 'audio/mp3':
        return 'audio/mpeg';
      case 'audio/m4a':
        return 'audio/x-m4a';
      case 'video/m4v':
        return 'video/x-m4v';
      default:
        return normalized;
    }
  }

  /// 确定最终的 MIME 类型
  static String determineMimeType({
    String? serverContentType,
    required String url,
  }) {
    if (serverContentType != null && serverContentType.isNotEmpty) {
      final normalized = normalizeMimeType(serverContentType);

      if (isKnownMediaFormat(normalized)) {
        return normalized;
      }

      if (normalized == 'application/octet-stream' ||
          normalized == 'binary/octet-stream') {
        final inferred = inferMimeTypeFromUrl(url);
        if (inferred != null) {
          log(
            () => 'Server returned generic type, inferred from URL: $inferred',
          );
          return inferred;
        }
      }

      return normalized;
    }

    final inferred = inferMimeTypeFromUrl(url);
    if (inferred != null) {
      log(() => 'No Content-Type from server, inferred from URL: $inferred');
      return inferred;
    }

    log(
      () =>
          'Cannot determine MIME type, using default: ${MediaProxyConfig.instance.defaultContentType}',
    );
    return MediaProxyConfig.instance.defaultContentType;
  }
}
