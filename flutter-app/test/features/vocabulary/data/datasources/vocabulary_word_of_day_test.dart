import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocabulary_remote_datasource.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

const _wordPayload = {
  'id': 'abc123',
  'word': 'ephemeral',
  'definition': 'lasting for a very short time',
  'translation': {'vi': 'phù du'},
  'pronunciation': '/ɪˈfem.ər.əl/',
  'audio_url': null,
  'part_of_speech': 'adjective',
  'difficulty_level': 'C1',
  'course_id': null,
  'lesson_id': null,
  'tags': ['academic', 'AWL'],
  'usage_frequency': 3,
  'created_at': '2026-06-14T08:00:00Z',
  'updated_at': '2026-06-14T08:00:00Z',
};

void main() {
  group('VocabularyRemoteDataSourceImpl.getWordOfDay', () {
    late ApiClient apiClient;
    late VocabularyRemoteDataSourceImpl datasource;

    setUp(() {
      apiClient = ApiClient(
        client: MockClient((request) async {
          expect(request.url.path, '/vocabulary/word-of-day');
          expect(request.method, 'GET');
          return http.Response(
            jsonEncode(_wordPayload),
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
        baseUrl: 'http://test.local',
        networkInfo: _AlwaysConnectedNetworkInfo(),
        enableLogging: false,
      );
      datasource = VocabularyRemoteDataSourceImpl(apiClient: apiClient);
    });

    test('calls GET /vocabulary/word-of-day and parses word', () async {
      final result = await datasource.getWordOfDay();
      expect(result.word, 'ephemeral');
      expect(result.difficultyLevel, 'C1');
      expect(result.pronunciation, '/ɪˈfem.ər.əl/');
    });

    test('maps Vietnamese translation', () async {
      final result = await datasource.getWordOfDay();
      expect(result.vietnameseTranslation, 'phù du');
    });

    test('maps tags list', () async {
      final result = await datasource.getWordOfDay();
      expect(result.tags, contains('AWL'));
    });
  });

  group('VocabularyRemoteDataSourceImpl.getWordOfDay — error handling', () {
    test('throws on non-200 response', () async {
      final client = ApiClient(
        client: MockClient((_) async => http.Response('Not Found', 404)),
        baseUrl: 'http://test.local',
        networkInfo: _AlwaysConnectedNetworkInfo(),
        enableLogging: false,
      );
      final ds = VocabularyRemoteDataSourceImpl(apiClient: client);
      expect(() => ds.getWordOfDay(), throwsA(anything));
    });
  });
}
