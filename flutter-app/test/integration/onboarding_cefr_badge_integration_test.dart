import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';

class _FakeApiClient extends ApiClient {
  _FakeApiClient() : super(baseUrl: 'http://test.local');

  @override
  Future<Map<String, dynamic>> get(
    String path, {
    Map<String, String>? headers,
    Duration? timeout,
  }) async {
    if (path == '/users/me/level-full') {
      return {
        'numeric_level': 4,
        'current_xp_in_level': 30,
        'xp_for_next_level': 100,
        'level_progress_percent': 30.0,
        'total_xp': 700,
        'cefr_level': 'B2',
        'cefr_name': 'Upper Intermediate',
        'rank': 'silver',
        'rank_name': 'Silver',
        'rank_score': 42.0,
      };
    }
    return <String, dynamic>{};
  }
}

void main() {
  group('Onboarding -> CEFR Badge Integration', () {
    testWidgets(
      'renders CEFR badge value immediately after onboarding completion refresh',
      (tester) async {
        final levelProvider = LevelProvider(apiClient: _FakeApiClient());
        var onboardingCompleted = false;

        await tester.pumpWidget(
          ChangeNotifierProvider<LevelProvider>.value(
            value: levelProvider,
            child: MaterialApp(
              home: Scaffold(
                body: Column(
                  children: [
                    const SizedBox(height: 16),
                    ElevatedButton(
                      key: const Key('complete-onboarding-button'),
                      onPressed: () async {
                        // Simulates AuthWrapper's post-onboarding callback path.
                        onboardingCompleted = true;
                        await levelProvider.fetchLevelFull();
                      },
                      child: const Text('Complete Onboarding'),
                    ),
                    Consumer<LevelProvider>(
                      builder: (context, provider, _) => Text(
                        'badge:${provider.proficiencyLevel}',
                        key: const Key('cefr-badge-text'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.byKey(const Key('complete-onboarding-button')));
        await tester.pumpAndSettle();

        expect(onboardingCompleted, isTrue);
        expect(find.byKey(const Key('cefr-badge-text')), findsOneWidget);
        expect(find.text('badge:B2'), findsOneWidget);
      },
    );
  });
}
