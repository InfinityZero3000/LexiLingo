import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_remote_datasource.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

void main() {
  group('ApiMistakeNotebookRemoteDataSource', () {
    test(
      'posts Flutter mistake payload to backend mistakes endpoint',
      () async {
        late http.Request capturedRequest;
        final dataSource = _dataSource(
          MockClient((request) async {
            capturedRequest = request;
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(request.method, 'POST');
            expect(request.url.path, '/api/v1/mistakes');
            expect(body['id'], 'mistake_remote');
            expect(body['source_type'], 'news_quiz');
            expect(body['selected_answer'], 'A');

            return _jsonResponse({
              'data': _entryJson(id: body['id'] as String),
            });
          }),
        );

        final saved = await dataSource.saveMistake(
          _entry(id: 'mistake_remote'),
        );

        expect(
          capturedRequest.headers['content-type'],
          contains('application/json'),
        );
        expect(saved.id, 'mistake_remote');
      },
    );

    test('lists entries from envelope list response', () async {
      final dataSource = _dataSource(
        MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/mistakes');
          expect(request.url.queryParameters['status'], 'all');
          expect(request.url.queryParameters['limit'], '100');
          expect(request.url.queryParameters['offset'], '0');

          return _jsonResponse({
            'data': [_entryJson(id: 'remote-1')],
          });
        }),
      );

      final entries = await dataSource.getEntries();

      expect(entries.map((entry) => entry.id), ['remote-1']);
    });

    test('patches review and deletes by id', () async {
      final requests = <String>[];
      final dataSource = _dataSource(
        MockClient((request) async {
          requests.add('${request.method} ${request.url.path}');
          if (request.method == 'PATCH') {
            return _jsonResponse({'data': _entryJson(id: 'remote-1')});
          }
          return _jsonResponse({'message': 'Mistake deleted'});
        }),
      );

      final reviewed = await dataSource.markReviewed('remote/1');
      await dataSource.delete('remote/1');

      expect(reviewed.id, 'remote-1');
      expect(requests, [
        'PATCH /api/v1/mistakes/remote%2F1/review',
        'DELETE /api/v1/mistakes/remote%2F1',
      ]);
    });
  });
}

ApiMistakeNotebookRemoteDataSource _dataSource(http.Client client) {
  return ApiMistakeNotebookRemoteDataSource(
    apiClient: ApiClient(
      client: client,
      baseUrl: 'https://api.example.test/api/v1',
      enableLogging: false,
      networkInfo: _AlwaysConnectedNetworkInfo(),
    ),
  );
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

MistakeNotebookEntry _entry({required String id}) {
  return MistakeNotebookEntry(
    id: id,
    sourceType: 'news_quiz',
    sourceId: 'article-1',
    sourceTitle: 'Demo article',
    question: 'What happened?',
    selectedAnswer: 'A',
    correctAnswer: 'B',
    explanation: 'Because the text says so.',
    skill: 'reading',
    createdAt: DateTime(2026),
  );
}

Map<String, dynamic> _entryJson({required String id}) => {
  'id': id,
  'source_type': 'news_quiz',
  'source_id': 'article-1',
  'source_title': 'Demo article',
  'question': 'What happened?',
  'selected_answer': 'A',
  'correct_answer': 'B',
  'explanation': 'Because the text says so.',
  'skill': 'reading',
  'status': 'open',
  'created_at': DateTime(2026).toIso8601String(),
  'updated_at': DateTime(2026).toIso8601String(),
  'review_count': 0,
  'attempt_count': 1,
};

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}
