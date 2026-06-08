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

void main() {
  group('VocabularyRemoteDataSourceImpl.getVocabularyItems', () {
    test('parses a list wrapped by ApiClient in the data field', () async {
      final httpClient = MockClient((request) async {
        expect(request.url.path, '/vocabulary/items');
        expect(request.url.queryParameters['limit'], '50');
        expect(request.url.queryParameters['offset'], '0');

        return http.Response(
          jsonEncode([
            {
              'id': '7f313ad4-2e6e-43f4-8231-27089da4cb64',
              'word': 'discover',
              'definition': 'to find something for the first time',
              'translation': {'vi': 'khám phá'},
              'pronunciation': '/dɪˈskʌvər/',
              'audio_url': null,
              'part_of_speech': 'verb',
              'difficulty_level': 'A2',
              'course_id': null,
              'lesson_id': null,
              'tags': ['general'],
              'usage_frequency': 10,
              'created_at': '2026-06-06T00:00:00Z',
              'updated_at': '2026-06-06T00:00:00Z',
            },
          ]),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      final apiClient = ApiClient(
        client: httpClient,
        baseUrl: 'http://test.local',
        networkInfo: _AlwaysConnectedNetworkInfo(),
        enableLogging: false,
      );
      final dataSource = VocabularyRemoteDataSourceImpl(apiClient: apiClient);

      final items = await dataSource.getVocabularyItems();

      expect(items, hasLength(1));
      expect(items.single.word, 'discover');
      expect(items.single.vietnameseTranslation, 'khám phá');
    });
  });
}
