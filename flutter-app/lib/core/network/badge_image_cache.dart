library;

import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

/// Dedicated cache bucket for achievement badges loaded from CDN URLs.
class BadgeImageCache {
  BadgeImageCache._();

  // Keep badge fetches snappy: if CDN is too slow, UI falls back to local assets.
  static const Duration networkTimeout = Duration(seconds: 4);

  static final CacheManager instance = CacheManager(
    Config(
      'lexilingo_badge_image_cache',
      stalePeriod: const Duration(days: 30),
      maxNrOfCacheObjects: 300,
      fileService: HttpFileService(
        httpClient: _TimeoutHttpClient(timeout: networkTimeout),
      ),
    ),
  );
}

class _TimeoutHttpClient extends http.BaseClient {
  _TimeoutHttpClient({required this.timeout})
    : _inner = IOClient(HttpClient()..connectionTimeout = timeout);

  final Duration timeout;
  final http.Client _inner;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    return _inner.send(request).timeout(timeout);
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
