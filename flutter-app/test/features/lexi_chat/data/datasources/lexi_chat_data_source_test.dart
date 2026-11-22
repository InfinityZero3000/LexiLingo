import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/lexi_chat/data/datasources/lexi_chat_data_source.dart';

class _Online implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

void main() {
  test(
    'createSession rethrows instead of inventing a local session id',
    () async {
      final source = LexiChatDataSource(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response('{"detail":"nope"}', 400),
          ),
          baseUrl: 'http://test',
          networkInfo: _Online(),
        ),
      );

      await expectLater(
        source.createSession(userId: 'u1'),
        throwsA(isA<ServerException>()),
      );
    },
  );
}
