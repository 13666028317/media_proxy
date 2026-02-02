import 'package:flutter_test/flutter_test.dart';

import 'package:media_proxy/media_proxy.dart';

void main() {
  test('MediaCacheProxy instance test', () {
    final instance = MediaCacheProxy.instance;
    expect(instance, isNotNull);
  });
}
