import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/daily_challenge_mapper.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';

DailyChallengeEntity _challenge({
  String title = 'Practice words',
  String description = 'Complete a vocabulary word challenge',
  String category = 'vocabulary',
  int xpReward = 30,
  bool isCompleted = false,
}) {
  return DailyChallengeEntity(
    id: 'daily-1',
    title: title,
    description: description,
    icon: 'word',
    category: category,
    target: 5,
    current: isCompleted ? 5 : 2,
    xpReward: xpReward,
    isCompleted: isCompleted,
    expiresAt: DateTime(2026, 7, 2),
  );
}

void main() {
  test('maps vocabulary daily challenge to word scramble', () {
    final challenge = _challenge();

    expect(gameTypeForDailyChallenge(challenge), GameType.wordScramble);
    expect(
      toGameDailyChallenge(challenge).gameType,
      GameType.wordScramble.apiKey,
    );
  });

  test('maps grammar daily challenge to grammar quiz', () {
    final challenge = _challenge(
      title: 'Grammar sprint',
      description: 'Answer 5 grammar questions',
      category: 'lesson',
    );

    expect(gameTypeForDailyChallenge(challenge), GameType.grammarQuiz);
  });

  test(
    'preserves completion and raises bonus multiplier for larger rewards',
    () {
      final mapped = toGameDailyChallenge(
        _challenge(xpReward: 50, isCompleted: true),
      );

      expect(mapped.completed, isTrue);
      expect(mapped.bonusMultiplier, 2);
      expect(mapped.targetScore, 5);
    },
  );
}
