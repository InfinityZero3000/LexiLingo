import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';

/// Keeps per-user state tied to the signed-in user. Providers outlive a
/// session, so without this a sign-out left the last learner's numbers in
/// memory and a sign-in showed them until something happened to reload.
abstract final class UserSessionSync {
  static void afterSignOut(BuildContext context) {
    _maybe<ProgressProvider>(context)?.reset();
    _maybe<StreakProvider>(context)?.reset();
    _maybe<LevelProvider>(context)?.reset();
    _maybe<ProficiencyProvider>(context)?.reset();
    _maybe<DailyChallengesProvider>(context)?.reset();
    _maybe<ContentActivityProvider>(context)?.reset();
    _maybe<HomeProvider>(context)?.clear();
  }

  static Future<void> afterSignIn(BuildContext context) async {
    final streak = _maybe<StreakProvider>(context);
    final level = _maybe<LevelProvider>(context);
    final home = _maybe<HomeProvider>(context);
    final challenges = _maybe<DailyChallengesProvider>(context);
    await Future.wait([
      if (streak != null) streak.loadStreak(),
      if (level != null) level.fetchLevelFull(),
      if (home != null) home.loadWeeklyProgress(),
      if (challenges != null) challenges.loadChallenges(),
    ]);
  }

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
