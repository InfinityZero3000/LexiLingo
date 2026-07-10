import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/daily_challenge_entity.dart';
import '../providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';

/// Daily Challenges Card for Home Screen
/// Shows today's challenges with progress
class DailyChallengesCard extends StatefulWidget {
  const DailyChallengesCard({super.key});

  @override
  State<DailyChallengesCard> createState() => _DailyChallengesCardState();
}

class _DailyChallengesCardState extends State<DailyChallengesCard> {
  @override
  void initState() {
    super.initState();
    // Load challenges when card is shown
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<DailyChallengesProvider>().loadChallenges();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Consumer<DailyChallengesProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.challenges.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark
                  ? AppColors.surfaceDarkMuted
                  : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.08)
                    : AppColors.grey200,
                width: 2,
              ),
            ),
            child: Column(
              children: [
                const LottieLoadingWidget.small(),
                const SizedBox(height: 12),
                Text(
                  'home.loadingChallenges'.tr(),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: AppColorRoles.textSecondary(isDark),
                  ),
                ),
              ],
            ),
          );
        }

        if (provider.challenges.isEmpty) {
          return const SizedBox.shrink();
        }

        final accent = AppColors.purple;

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showChallengesSheet(context, provider),
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.surfaceDarkMuted
                    : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isDark
                      ? accent.withValues(alpha: 0.35)
                      : accent.withValues(alpha: 0.22),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? Colors.black.withValues(alpha: 0.3)
                        : accent.withValues(alpha: 0.12),
                    blurRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const AppGameIcon(
                          GameIcon.star,
                          size: 22,
                          fallbackColor: AppColors.purple,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'home.dailyChallenges'.tr(),
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: AppColorRoles.textPrimary(isDark),
                              ),
                            ),
                            Text(
                              'home.challengesCompleted'.tr(
                                namedArgs: {
                                  'completed': '${provider.completedCount}',
                                  'total': '${provider.totalChallenges}',
                                },
                              ),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: AppColorRoles.textSecondary(isDark),
                              ),
                            ),
                          ],
                        ),
                      ),
                      // XP earned
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.warning.withValues(
                            alpha: isDark ? 0.22 : 0.16,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: AppColors.warning.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const AppGameIcon(
                              GameIcon.star,
                              size: 13,
                              fallbackColor: AppColors.warningDark,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '+${provider.xpEarned} XP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? AppColors.warning
                                    : AppColors.warningDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: provider.progress,
                      backgroundColor: isDark
                          ? Colors.white.withValues(alpha: 0.1)
                          : AppColors.grey200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        provider.allCompleted
                            ? AppColors.greenSuccessBright
                            : AppColors.purple,
                      ),
                      minHeight: 5,
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Mini challenge list
                  ...provider.challenges.take(3).map((challenge) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _buildMiniChallenge(context, challenge, provider),
                    );
                  }),

                  // View all button
                  if (provider.challenges.length > 3)
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            _showChallengesSheet(context, provider),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(44, 44),
                        ),
                        child: Text(
                          'home.viewAllChallenges'.tr(
                            namedArgs: {
                              'count': '${provider.challenges.length}',
                            },
                          ),
                          style: TextStyle(
                            color: isDark
                                ? AppColors.purpleLight
                                : AppColors.purple,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniChallenge(
    BuildContext context,
    DailyChallengeEntity challenge,
    DailyChallengesProvider provider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(challenge.category, isDark: isDark);
    final textMuted = AppColorRoles.textSecondary(isDark);
    return Row(
      children: [
        AppGameIcon(
          _getCategoryIcon(challenge.category),
          size: 18,
          fallbackColor: categoryColor,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            challenge.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              decoration: challenge.isCompleted
                  ? TextDecoration.lineThrough
                  : null,
              color: challenge.isCompleted
                  ? textMuted
                  : AppColorRoles.textPrimary(isDark),
            ),
          ),
        ),
        if (challenge.isCompleted)
          AppGameIcon(
            GameIcon.checkmark,
            size: 20,
            fallbackColor: AppColors.greenSuccessBright,
          )
        else
          Text(
            '${challenge.current}/${challenge.target}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: textMuted),
          ),
      ],
    );
  }

  void _showChallengesSheet(
    BuildContext context,
    DailyChallengesProvider provider,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => DailyChallengesSheet(provider: provider),
    );
  }

  Color _getCategoryColor(String category, {bool isDark = false}) {
    switch (category) {
      case 'lesson':
        return AppColorRoles.primary(isDark);
      case 'vocabulary':
        return AppColors.purple;
      case 'streak':
        return AppColors.deepOrange;
      case 'xp':
        return isDark ? AppColors.warning : AppColors.warningDark;
      case 'voice':
        return Colors.pink;
      case 'social':
        return AppColors.teal;
      default:
        return AppColors.grey500;
    }
  }

  GameIcon _getCategoryIcon(String category) {
    switch (category) {
      case 'lesson':
        return GameIcon.lessonBoard;
      case 'vocabulary':
        return GameIcon.book;
      case 'streak':
        return GameIcon.streakFire;
      case 'xp':
        return GameIcon.bolt;
      case 'voice':
        return GameIcon.microphone;
      case 'social':
        return GameIcon.peoplePair;
      default:
        return GameIcon.star;
    }
  }
}

/// Full Daily Challenges Bottom Sheet
class DailyChallengesSheet extends StatelessWidget {
  final DailyChallengesProvider provider;

  const DailyChallengesSheet({super.key, required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.purple;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.2)
                    : AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              AppGameIcon(
                GameIcon.star,
                size: 28,
                fallbackColor: isDark ? AppColors.purpleLight : accent,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.dailyChallenges'.tr(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColorRoles.textPrimary(isDark),
                      ),
                    ),
                    Text(
                      'home.completeBonusXp'.tr(
                        namedArgs: {'xp': '${provider.bonusXp}'},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? AppColors.purpleLight : accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Progress
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: provider.progress,
                    backgroundColor: isDark
                        ? Colors.white.withValues(alpha: 0.1)
                        : AppColors.grey200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.allCompleted
                          ? AppColors.greenSuccessBright
                          : accent,
                    ),
                    minHeight: 12,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${provider.completedCount}/${provider.totalChallenges}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColorRoles.textPrimary(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Challenges list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: provider.challenges.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final challenge = provider.challenges[index];
                return _ChallengeCard(
                  challenge: challenge,
                  onClaim: () => _claimReward(context, challenge.id),
                  isClaimed: provider.isRewardClaimed(challenge.id),
                );
              },
            ),
          ),

          // Bonus section (if all completed)
          if (provider.allCompleted) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: isDark
                      ? [
                          AppColors.warning.withValues(alpha: 0.3),
                          AppColors.orange.withValues(alpha: 0.3),
                        ]
                      : AppColors.warmGradient
                            .map((c) => c.withValues(alpha: 0.22))
                            .toList(),
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: AppColors.orange.withValues(alpha: 0.35),
                  width: 2,
                ),
              ),
              child: Row(
                children: [
                  AppGameIcon(
                    GameIcon.trophy,
                    size: 36,
                    fallbackColor: isDark
                        ? AppColors.warning
                        : AppColors.warningDark,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'home.allChallengesComplete'.tr(),
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColorRoles.textPrimary(isDark),
                          ),
                        ),
                        Text(
                          'home.bonusXpEarned'.tr(
                            namedArgs: {'xp': '${provider.bonusXp}'},
                          ),
                          style: TextStyle(
                            color: isDark
                                ? AppColors.warning
                                : AppColors.deepOrange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const AppGameIcon(
                    GameIcon.checkmark,
                    size: 32,
                    fallbackColor: AppColors.greenSuccessBright,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  void _claimReward(BuildContext context, String challengeId) async {
    final challenge = provider.challenges.firstWhere(
      (c) => c.id == challengeId,
    );
    final success = await provider.claimReward(challengeId);
    if (success && context.mounted) {
      // Optimistically update XP immediately so the header reflects it right away.
      final levelProvider = context.read<LevelProvider>();
      levelProvider.updateLevel(levelProvider.totalXp + challenge.xpReward);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('home.rewardClaimed'.tr()),
          backgroundColor: AppColors.greenSuccessBright,
        ),
      );
      // Sync with server in background to apply any XP-boost multipliers.
      levelProvider.fetchLevelFull();
    }
  }
}

/// Individual Challenge Card
class _ChallengeCard extends StatelessWidget {
  final DailyChallengeEntity challenge;
  final VoidCallback onClaim;
  final bool isClaimed;

  const _ChallengeCard({
    required this.challenge,
    required this.onClaim,
    required this.isClaimed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final categoryColor = _getCategoryColor(challenge.category, isDark: isDark);
    final textMuted = AppColorRoles.textSecondary(isDark);

    final completedBg = isDark
        ? AppColors.greenSuccessBright.withValues(alpha: 0.12)
        : AppColors.greenSuccessBg;
    final completedBorder = isDark
        ? AppColors.greenSuccessBright.withValues(alpha: 0.4)
        : AppColors.greenSuccessSoft.withValues(alpha: 0.6);
    final defaultBg = isDark
        ? AppColors.surfaceDarkMuted
        : AppColors.surfaceLight;
    final defaultBorder = isDark
        ? Colors.white.withValues(alpha: 0.1)
        : AppColors.grey200;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: challenge.isCompleted ? completedBg : defaultBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: challenge.isCompleted ? completedBorder : defaultBorder,
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withValues(alpha: 0.25)
                : Colors.black.withValues(alpha: 0.04),
            blurRadius: 0,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: categoryColor.withValues(alpha: isDark ? 0.25 : 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: AppGameIcon(
                _getCategoryIcon(challenge.category),
                size: 26,
                fallbackColor: categoryColor,
              ),
            ),
          ),
          const SizedBox(width: 12),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  challenge.title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                    decoration: challenge.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  challenge.description,
                  style: theme.textTheme.bodySmall?.copyWith(color: textMuted),
                ),
                const SizedBox(height: 8),
                // Progress bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: challenge.progress,
                          backgroundColor: isDark
                              ? Colors.white.withValues(alpha: 0.1)
                              : AppColors.grey200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            challenge.isCompleted
                                ? AppColors.greenSuccessBright
                                : categoryColor,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${challenge.current}/${challenge.target}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: textMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Reward/Status
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.warning.withValues(
                    alpha: isDark ? 0.22 : 0.16,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.warning.withValues(alpha: 0.4),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppGameIcon(
                      GameIcon.star,
                      size: 12,
                      fallbackColor: isDark
                          ? AppColors.warning
                          : AppColors.warningDark,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${challenge.xpReward}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? AppColors.warning
                            : AppColors.warningDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (challenge.isCompleted)
                if (isClaimed)
                  const AppGameIcon(
                    GameIcon.checkmark,
                    size: 28,
                    fallbackColor: AppColors.greenSuccessBright,
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(
                      minHeight: 44,
                      minWidth: 44,
                    ),
                    child: ElevatedButton(
                      onPressed: onClaim,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.greenSuccessBright,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        textStyle: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text('home.claimReward'.tr()),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category, {bool isDark = false}) {
    switch (category) {
      case 'lesson':
        return AppColorRoles.primary(isDark);
      case 'vocabulary':
        return AppColors.purple;
      case 'streak':
        return AppColors.deepOrange;
      case 'xp':
        return isDark ? AppColors.warning : AppColors.warningDark;
      case 'voice':
        return Colors.pink;
      case 'social':
        return AppColors.teal;
      default:
        return AppColors.grey500;
    }
  }

  GameIcon _getCategoryIcon(String category) {
    switch (category) {
      case 'lesson':
        return GameIcon.lessonBoard;
      case 'vocabulary':
        return GameIcon.book;
      case 'streak':
        return GameIcon.streakFire;
      case 'xp':
        return GameIcon.bolt;
      case 'voice':
        return GameIcon.microphone;
      case 'social':
        return GameIcon.peoplePair;
      default:
        return GameIcon.star;
    }
  }
}
