import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/network_info.dart';
import 'package:lexilingo_app/features/auth/data/public_stats_service.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/welcome_page.dart';

class _Online implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}

Future<void> _pump(WidgetTester tester, PublicStatsLoader loader) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: WelcomePage(onGetStarted: () {}, onSkip: () {}, loadStats: loader),
    ),
  );
  await tester.pump(const Duration(seconds: 1));
}

PublicStatsService _service(http.Response Function(http.Request) handler) =>
    PublicStatsService(
      apiClient: ApiClient(
        baseUrl: 'http://stats.invalid/api/v1',
        networkInfo: _Online(),
        client: MockClient((request) async => handler(request)),
      ),
    );

void main() {
  testWidgets('never shows the old invented 50k+ and 12k+', (tester) async {
    await _pump(tester, () async => null);

    expect(find.text('50k+'), findsNothing);
    expect(find.text('12k+'), findsNothing);
  });

  testWidgets('shows the real numbers the server reports', (tester) async {
    await _pump(
      tester,
      () async => const PublicStats(learners: 1234, lessonsToday: 56),
    );

    expect(find.text('1.23K'), findsOneWidget);
    expect(find.text('56'), findsOneWidget);
  });

  testWidgets('the page does not move when the numbers arrive', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: WelcomePage(
          onGetStarted: () {},
          onSkip: () {},
          loadStats: () => Future.delayed(
            const Duration(milliseconds: 500),
            () => const PublicStats(learners: 10, lessonsToday: 2),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    final before = tester.getTopLeft(find.byType(OutlinedButton)).dy;
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('10'), findsOneWidget);
    expect(tester.getTopLeft(find.byType(OutlinedButton)).dy, before);
  });

  group('PublicStatsService', () {
    http.Response ok(Map<String, dynamic> body) =>
        http.Response(jsonEncode(body), 200);

    test('returns the numbers when show is true', () async {
      final stats = await _service(
        (_) =>
            ok({'learners': 900, 'lessons_completed_today': 40, 'show': true}),
      ).fetch();

      expect(stats?.learners, 900);
      expect(stats?.lessonsToday, 40);
    });

    test('returns null when show is false', () async {
      final stats = await _service(
        (_) => ok({'learners': 9, 'lessons_completed_today': 4, 'show': false}),
      ).fetch();

      expect(stats, isNull);
    });

    test('returns null on a server error or a malformed body', () async {
      expect(await _service((_) => http.Response('{}', 500)).fetch(), isNull);
      expect(await _service((_) => ok({'show': true})).fetch(), isNull);
    });

    test('asks the public endpoint', () async {
      late Uri asked;
      await _service((request) {
        asked = request.url;
        return ok({'show': false});
      }).fetch();

      expect(asked.path, '/api/v1/public/stats');
    });
  });
}
