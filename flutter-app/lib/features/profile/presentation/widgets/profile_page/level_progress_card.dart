import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_ui_components.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class ProfileLevelProgressCard extends StatelessWidget {
  const ProfileLevelProgressCard({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        final level = levelProvider.displayLevel;
        final xpIn = levelProvider.displayXpInLevel;
        final xpFor = levelProvider.displayXpForNextLevel;
        final progress = levelProvider.displayLevelProgress;

        return GlassmorphicContainer(
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.levelRange'.tr(
                      namedArgs: {
                        'level': '$level',
                        'nextLevel': '${level + 1}',
                      },
                    ),
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'profile.xpProgress'.tr(
                      namedArgs: {'current': '$xpIn', 'total': '$xpFor'},
                    ),
                    style: const TextStyle(fontSize: 14),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: AppColorRoles.primary(
                    isDark,
                  ).withValues(alpha: 0.18),
                  valueColor: AlwaysStoppedAnimation<Color>(
                    AppColorRoles.primary(isDark),
                  ),
                  minHeight: 12,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'profile.xpToNextLevel'.tr(
                      namedArgs: {
                        'xp': '${xpFor - xpIn}',
                        'level': '${level + 1}',
                      },
                    ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  Text(
                    'profile.percentComplete'.tr(
                      namedArgs: {
                        'percent': (progress * 100).toStringAsFixed(0),
                      },
                    ),
                    style: TextStyle(
                      color: AppColorRoles.primary(isDark),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
