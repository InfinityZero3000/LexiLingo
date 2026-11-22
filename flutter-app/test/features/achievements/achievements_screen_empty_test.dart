import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/unlocked_achievement.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:provider/provider.dart';

class _EmptyRepo implements AchievementRepository {
  @override
  Future<List<AchievementEntity>> getAllAchievements() async => [];
  @override
  Future<List<UserAchievementEntity>> getMyAchievements() async => [];
  @override
  Future<List<UnlockedAchievement>> checkAllAchievements() async => [];
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('empty response shows the empty state and a learning action', (
    tester,
  ) async {
    final pushed = <String?>[];
    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AchievementProvider(repository: _EmptyRepo()),
        child: MaterialApp(
          home: const AchievementsScreen(),
          onGenerateRoute: (settings) {
            pushed.add(settings.name);
            return MaterialPageRoute<void>(
              settings: settings,
              builder: (_) => const Scaffold(body: Text('learning tab')),
            );
          },
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('achievements.emptyTitle'), findsOneWidget);
    expect(find.text('achievements.emptyBody'), findsOneWidget);
    expect(find.text('achievements.emptyAction'), findsOneWidget);

    await tester.tap(find.text('achievements.emptyAction'));
    await tester.pump();
    expect(pushed, contains('/courses'));
  });
}
