import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';
import 'package:easy_localization/easy_localization.dart';

GameType gameTypeForDailyChallenge(DailyChallengeEntity challenge) {
  final haystack = [
    challenge.category,
    challenge.title,
    challenge.description,
    challenge.icon,
  ].join(' ').toLowerCase();

  if (haystack.contains('grammar')) return GameType.grammarQuiz;
  if (haystack.contains('listening') || haystack.contains('blank')) {
    return GameType.fillBlank;
  }
  if (haystack.contains('voice') ||
      haystack.contains('speak') ||
      haystack.contains('pronunciation')) {
    return GameType.spellingBee;
  }
  if (haystack.contains('match')) return GameType.matching;
  if (haystack.contains('hangman')) return GameType.hangman;
  if (haystack.contains('vocab') || haystack.contains('word')) {
    return GameType.wordScramble;
  }
  return GameType.fillBlank;
}

DailyChallenge toGameDailyChallenge(DailyChallengeEntity challenge) {
  final gameType = gameTypeForDailyChallenge(challenge);
  final description = challenge.description.trim().isNotEmpty
      ? challenge.description.trim()
      : challenge.title.trim();

  return DailyChallenge(
    gameType: gameType.apiKey,
    description: description.isNotEmpty
        ? description
        : 'games.completeTodayChallenge'.tr(),
    targetScore: challenge.target,
    bonusMultiplier: challenge.xpReward >= 40 ? 2 : 1,
    completed: challenge.isCompleted,
    resetsAt: challenge.expiresAt,
  );
}
