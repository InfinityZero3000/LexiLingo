import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/network/response_models.dart';

class _ConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

void main() {
  test('preserves structured backend error for a failed 401 refresh', () async {
    final client = ApiClient(
      baseUrl: 'https://api.example.test',
      enableLogging: false,
      networkInfo: _ConnectedNetworkInfo(),
      onUnauthorized: () async => false,
      client: MockClient(
        (_) async => http.Response(
          '''
          {
            "error": {
              "code": "AUTH_INVALID",
              "message": "Invalid Google ID token",
              "details": null
            },
            "meta": {
              "request_id": "test-request",
              "timestamp": "2026-06-09T00:00:00Z"
            }
          }
          ''',
          401,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );

    expect(
      () => client.postEnvelope<Map<String, dynamic>>(
        '/auth/google',
        body: const {'id_token': 'invalid', 'source': 'app'},
        fromJson: (data) => data as Map<String, dynamic>,
      ),
      throwsA(
        isA<ApiErrorException>()
            .having((error) => error.code, 'code', 'AUTH_INVALID')
            .having(
              (error) => error.message,
              'message',
              'Invalid Google ID token',
            ),
      ),
    );

    client.close();
  });
}
