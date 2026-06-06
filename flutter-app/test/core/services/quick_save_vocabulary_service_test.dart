import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

void main() {
  test('emits saved word after quick-save succeeds', () async {
    final apiClient = ApiClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/vocabulary/collection/quick-save');

        return http.Response(
          jsonEncode({
            'normalized_word': 'resilient',
            'created_new_item': true,
            'already_in_collection': false,
            'vocabulary': {'id': 'vocab-1'},
          }),
          201,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://test.local',
      networkInfo: _AlwaysConnectedNetworkInfo(),
      enableLogging: false,
    );
    final service = QuickSaveVocabularyService(apiClient: apiClient);
    final emittedResult = service.savedWords.first;

    final result = await service.quickSaveWord(
      word: 'Resilient',
      sourceType: 'lexi_chat',
      sourceReference: 'message-1',
    );

    expect(result.normalizedWord, 'resilient');
    expect((await emittedResult).vocabularyId, 'vocab-1');
    service.dispose();
  });
}
