import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:lexilingo_app/features/youtube/data/repositories/youtube_repository.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';

/// Same contract as LocalCacheService.getOrFetch: store what the fetch returns,
/// and answer null when it throws and nothing is stored.
class _MemoryCache implements LocalCacheService {
  final store = <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> getOrFetch({
    required String key,
    required String type,
    required Future<Map<String, dynamic>> Function() fetchFn,
  }) async {
    if (store.containsKey(key)) return store[key];
    try {
      return store[key] = await fetchFn();
    } catch (_) {
      return null;
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

YouTubeRepository _repo(_MemoryCache cache, Map<String, dynamic> Function() body,
    {int status = 200, List<int>? calls}) {
  return YouTubeRepository(
    cache: cache,
    client: MockClient((request) async {
      calls?.add(1);
      return http.Response(jsonEncode(body()), status);
    }),
  );
}

void main() {
  const line = {'start_ms': 0, 'end_ms': 1000, 'text': 'Hello'};

  test('segments are ready and cached', () async {
    final cache = _MemoryCache();
    final calls = <int>[];
    final repo = _repo(cache, () => {'segments': [line], 'status': 'ok'}, calls: calls);

    final first = await repo.getCaptions('vid');
    final second = await repo.getCaptions('vid');

    expect(first.status, CaptionsStatus.ready);
    expect(first.segments.single.text, 'Hello');
    expect(second.status, CaptionsStatus.ready);
    expect(calls, hasLength(1));
  });

  test('a video without captions is none, an older backend without status too', () async {
    final repo = _repo(_MemoryCache(), () => {'segments': []});

    expect((await repo.getCaptions('vid')).status, CaptionsStatus.none);
  });

  test('unavailable is never stored, so the next try asks again', () async {
    final cache = _MemoryCache();
    var answer = <String, dynamic>{'segments': [], 'status': 'unavailable'};
    final calls = <int>[];
    final repo = _repo(cache, () => answer, calls: calls);

    expect((await repo.getCaptions('vid')).status, CaptionsStatus.unavailable);
    expect(cache.store, isEmpty);

    answer = {'segments': [line], 'status': 'ok'};
    expect((await repo.getCaptions('vid')).status, CaptionsStatus.ready);
    expect(calls, hasLength(2));
  });

  test('a failed request reads as unavailable, not as no subtitles', () async {
    final repo = _repo(_MemoryCache(), () => {'error': 'x'}, status: 503);

    expect((await repo.getCaptions('vid')).status, CaptionsStatus.unavailable);
  });

  test('provider exposes the status and a retry recovers', () async {
    final cache = _MemoryCache();
    var answer = <String, dynamic>{'segments': [], 'status': 'unavailable'};
    final provider = YouTubeProvider(repository: _repo(cache, () => answer));

    await provider.loadCaptions('vid');
    expect(provider.captionsStatus, CaptionsStatus.unavailable);
    expect(provider.captions, isEmpty);

    answer = {'segments': [line], 'status': 'ok'};
    await provider.loadCaptions('vid');
    expect(provider.captionsStatus, CaptionsStatus.ready);
    expect(provider.captions, hasLength(1));
  });
}
