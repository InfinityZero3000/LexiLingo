import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/gamification/data/datasources/gamification_remote_data_source.dart';

class _RecordingApi extends Fake implements ApiClient {
  String? path;
  Object? body;

  @override
  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) async {
    this.path = path;
    this.body = body;
    return {
      'success': true,
      'data': {
        'effects_applied': {'rescue': true, 'chance': 0.3},
      },
    };
  }
}

void main() {
  test('useItem sends game_session_id and returns the server roll', () async {
    final api = _RecordingApi();
    final effects = await GamificationRemoteDataSourceImpl(
      api,
    ).useItem('inv-1', gameSessionId: 'sess-1');

    expect(api.path, '/gamification/inventory/use');
    expect(api.body, {'inventory_id': 'inv-1', 'game_session_id': 'sess-1'});
    expect(effects?['rescue'], true);
  });

  test('useItem omits game_session_id when none is given', () async {
    final api = _RecordingApi();
    await GamificationRemoteDataSourceImpl(api).useItem('inv-1');

    expect(api.body, {'inventory_id': 'inv-1'});
  });
}
