import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/points_calendar_dialog.dart';

class StreakCardSection extends StatelessWidget {
  const StreakCardSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer2<HomeProvider, StreakProvider>(
      builder: (context, provider, streakProvider, child) {
        final streak = streakProvider.streak;
        final currentStreak = streak?.currentStreak ?? provider.streakDays;
        final longestStreak = streak?.longestStreak ?? 0;
        final isActiveToday = streak?.isActiveToday ?? false;

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: AnimatedStreakCard(
            streakDays: currentStreak,
            longestStreak: longestStreak,
            isActiveToday: isActiveToday,
            weeklyActivity: streak?.weeklyActivity,
            weeklyProgressPercentages: provider.weeklyProgress.weekProgress
                .map((day) => day.progressPercentage)
                .toList(growable: false),
            onTap: () {
              if (streak != null) {
                showPointsCalendarDialog(context, streak);
              }
            },
          ),
        );
      },
    );
  }
}
