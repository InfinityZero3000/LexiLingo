import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';

class _ConnectedNetworkInfo implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

void main() {
  test('flush sends queued events in one batch', () async {
    Map<String, dynamic>? requestBody;
    final apiClient = ApiClient(
      client: MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/analytics/events');
        requestBody = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({'accepted': 2}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://test.local',
      networkInfo: _ConnectedNetworkInfo(),
      enableLogging: false,
    );
    final service = AnalyticsService(
      apiClient: apiClient,
      flushInterval: const Duration(hours: 1),
    );

    service.track(
      'session_summary_shown',
      source: 'topic_chat',
      properties: const {'mistakes_saved': 2},
    );
    service.track('card_tapped', source: 'today_plan');

    await service.flush();

    final body = requestBody!;
    final events = body['events'] as List<dynamic>;
    final firstEvent = events[0] as Map<String, dynamic>;
    final secondEvent = events[1] as Map<String, dynamic>;
    expect(events, hasLength(2));
    expect(firstEvent['event_name'], 'session_summary_shown');
    expect(firstEvent['source'], 'topic_chat');
    expect(firstEvent['properties'], {'mistakes_saved': 2});
    expect(firstEvent['event_id'], isA<String>());
    expect(firstEvent['client_timestamp'], isA<String>());
    expect(secondEvent['event_name'], 'card_tapped');
    expect(secondEvent['source'], 'today_plan');
    expect(secondEvent['properties'], <String, dynamic>{});
    expect(secondEvent['client_timestamp'], isA<String>());
    expect(
      DateTime.parse(firstEvent['client_timestamp'] as String).isUtc,
      isTrue,
    );

    service.dispose();
    apiClient.close();
  });

  test('flush swallows transport failures', () async {
    final apiClient = ApiClient(
      client: MockClient((_) async => throw StateError('network unavailable')),
      baseUrl: 'http://test.local',
      networkInfo: _ConnectedNetworkInfo(),
      enableLogging: false,
    );
    final service = AnalyticsService(
      apiClient: apiClient,
      flushInterval: const Duration(hours: 1),
    );
    service.track(
      'achievement_unlock_overlay_shown',
      source: 'achievements',
    );

    await expectLater(service.flush(), completes);

    service.dispose();
    apiClient.close();
  });

  test('flush schedules events queued during a slow send', () async {
    final firstRequestStarted = Completer<void>();
    final releaseFirstRequest = Completer<void>();
    final secondRequestSent = Completer<void>();
    var requestCount = 0;
    final apiClient = ApiClient(
      client: MockClient((_) async {
        requestCount++;
        if (requestCount == 1) {
          firstRequestStarted.complete();
          await releaseFirstRequest.future;
        } else {
          secondRequestSent.complete();
        }
        return http.Response(
          jsonEncode({'accepted': 1}),
          202,
          headers: {'content-type': 'application/json'},
        );
      }),
      baseUrl: 'http://test.local',
      networkInfo: _ConnectedNetworkInfo(),
      enableLogging: false,
    );
    final service = AnalyticsService(
      apiClient: apiClient,
      flushInterval: const Duration(milliseconds: 10),
    );

    service.track('session_summary_shown', source: 'topic_chat');
    final firstFlush = service.flush();
    await firstRequestStarted.future;
    service.track('card_tapped', source: 'today_plan');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    releaseFirstRequest.complete();
    await firstFlush;
    await secondRequestSent.future.timeout(const Duration(seconds: 1));

    expect(requestCount, 2);
    service.dispose();
    apiClient.close();
  });
}
