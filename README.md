# Media Proxy

A Flutter package that provides a local HTTP proxy for caching and prefetching media files (like MP4) to improve playback performance. It acts as an intermediary between your media player and the remote server, handling caching, range requests, and aggressive prefetching.

## Features

- **Local HTTP Proxy**: Intercepts media requests and serves them from a local cache.
- **Smart Caching**: Efficiently stores and retrieves media segments.
- **Aggressive Prefetching**: Predictively downloads upcoming segments to minimize buffering.
- **MP4 Optimization**: Automatically handles `moov` atom placement for faster startup.
- **Global Download Queue**: Manages concurrent downloads across different media tasks.
- **Cache Management**: LRU-based cache cleanup and statistics.
- **Preload Scheduler**: Easily schedule media preloading.

## Getting started

Add `media_proxy` to your `pubspec.yaml`:

```yaml
dependencies:
  media_proxy:
    path: ../media_proxy # Or use the pub.dev version once published
```

## Usage

### Basic Setup

Start the proxy and get a proxied URL for your media:

```dart
import 'package:media_proxy/media_proxy.dart';

// Start the proxy and get the proxied URL
final originalUrl = 'https://example.com/video.mp4';
final proxyUrl = await MediaCacheProxy.getProxyUrl(originalUrl);

// Use the proxyUrl with your favorite video player (e.g., video_player, chewie)
// videoPlayerController = VideoPlayerController.network(proxyUrl);
```

### Preloading Media

You can preload media to ensure smooth playback when the user starts watching:

```dart
await MediaCacheProxy.preload(
  'https://example.com/video.mp4',
  segmentCount: 2, // Number of initial segments to preload
  includeMoov: true, // Ensure MP4 metadata is preloaded
);
```

### Cache Management

```dart
// Get cache statistics
final stats = await MediaCacheProxy.getCacheStats();
print('Cache size: ${stats['totalSizeMB']} MB');

// Clear all cache
await MediaCacheProxy.clearCache();
```

## Additional information

For more details on how the proxy works and how to customize the cache strategy, please refer to the documentation in the `lib/` directory.

### Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

### Issues

If you encounter any issues, please file them on the [GitHub repository](https://github.com/your-username/media_proxy/issues).
