import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Social stats row showing XP, followers, following
class SocialStatsRow extends StatelessWidget {
  const SocialStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<ProfileProvider>(
      builder: (context, profileProvider, _) {
        final stats = profileProvider.stats;

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            AnimatedSocialStat(
              value: '${stats?.totalVocabularyMastered ?? 0}',
              label: 'profile.words'.tr(),
              icon: Icons.spellcheck_rounded,
              color: AppColors.greenSuccessBright,
            ),
            Container(
              height: 40,
              width: 1,
              color: AppColors.grey400.withValues(alpha: 0.5),
            ),
            AnimatedSocialStat(
              value: '${stats?.totalLessonsCompleted ?? 0}',
              label: 'profile.lessons'.tr(),
              icon: Icons.menu_book,
              color: AppColorRoles.primary(
                Theme.of(context).brightness == Brightness.dark,
              ),
            ),
            Container(
              height: 40,
              width: 1,
              color: AppColors.grey400.withValues(alpha: 0.5),
            ),
            AnimatedSocialStat(
              value: '${stats?.currentStreak ?? 0}',
              label: 'profile.dayStreak'.tr(),
              icon: Icons.local_fire_department,
              color: AppColors.dangerGradient[0],
            ),
          ],
        );
      },
    );
  }
}
