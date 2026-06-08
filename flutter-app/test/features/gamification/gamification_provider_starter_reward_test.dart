import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

class _AlwaysConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

void main() {
  test('does not request starter reward when rollout is disabled', () async {
    var requestCount = 0;
    final provider = GamificationProvider(
      apiClient: _apiClient((request) async {
        requestCount++;
        return http.Response('{}', 500);
      }),
      enableStarterReward: false,
    );

    final reward = await provider.loadPendingStarterReward();

    expect(reward, isNull);
    expect(requestCount, 0);
    provider.dispose();
  });

  test('loads starter reward when rollout is enabled', () async {
    final provider = GamificationProvider(
      apiClient: _apiClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/gamification/rewards/starter/pending');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'reward_key': 'new_user_starter_gems_v1',
              'gems_awarded': 100,
              'current_balance': 100,
              'title': 'Welcome gift',
              'body': '100 Gems have been added to your wallet.',
            },
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
      enableStarterReward: true,
    );

    final reward = await provider.loadPendingStarterReward();

    expect(reward?.gemsAwarded, 100);
    expect(provider.pendingStarterReward?.currentBalance, 100);
    provider.dispose();
  });
}

ApiClient _apiClient(
  Future<http.Response> Function(http.Request request) handler,
) {
  return ApiClient(
    client: MockClient(handler),
    baseUrl: 'http://test.local',
    networkInfo: _AlwaysConnectedNetworkInfo(),
    enableLogging: false,
  );
}
