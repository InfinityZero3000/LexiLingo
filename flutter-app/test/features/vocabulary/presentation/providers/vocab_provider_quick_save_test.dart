import 'dart:convert';

import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

class _EmptyVocabRepository implements VocabRepository {
  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async {
    return const Right(null);
  }

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async {
    return const Right([]);
  }
}

void main() {
  test('reloads backend collection after a global quick-save event', () async {
    var saved = false;
    final apiClient = ApiClient(
      client: MockClient((request) async {
        if (request.method == 'POST') {
          saved = true;
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
        }

        expect(request.url.path, '/vocabulary/collection');
        expect(request.url.queryParameters['limit'], '100');

        return http.Response(
          jsonEncode({
            'items': saved
                ? [
                    {
                      'status': 'learning',
                      'vocabulary': {
                        'word': 'resilient',
                        'definition': 'able to recover quickly',
                        'pronunciation': '/rɪˈzɪliənt/',
                        'audio_url': null,
                        'part_of_speech': 'adjective',
                      },
                    },
                  ]
                : <Object>[],
            'total': saved ? 1 : 0,
            'limit': 100,
            'offset': 0,
            'has_more': false,
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://test.local',
      networkInfo: _AlwaysConnectedNetworkInfo(),
      enableLogging: false,
    );
    final quickSaveService = QuickSaveVocabularyService(apiClient: apiClient);
    final repository = _EmptyVocabRepository();
    final provider = VocabProvider(
      getWordsUseCase: GetWordsUseCase(repository),
      addWordUseCase: AddWordUseCase(repository),
      apiClient: apiClient,
      quickSaveService: quickSaveService,
    );

    await _waitUntil(() => !provider.isLoading);
    expect(provider.words, isEmpty);

    await quickSaveService.quickSaveWord(
      word: 'resilient',
      sourceType: 'topic_chat',
      sourceReference: 'message-2',
    );
    await _waitUntil(
      () => provider.words.any((word) => word.word == 'resilient'),
    );

    expect(provider.words.single.definition, 'able to recover quickly');
    provider.dispose();
    quickSaveService.dispose();
  });
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for asynchronous vocabulary refresh');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
