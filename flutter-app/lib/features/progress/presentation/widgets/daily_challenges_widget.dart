import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/daily_challenge_entity.dart';
import '../providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: isDark
                    ? AppColors.onGradient.withValues(alpha: 0.08)
                    : Theme.of(context).colorScheme.outlineVariant,

                width: 2,
              ),
            ),
            child: Column(
              children: [
                const LottieLoadingWidget.small(),
                const SizedBox(height: AppSpacing.md),
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
            child: Ink(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
                border: Border.all(
                  color: isDark
                      ? accent.withValues(alpha: 0.35)
                      : accent.withValues(alpha: 0.22),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isDark
                        ? AppColors.slate900.withValues(alpha: 0.3)
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
                        padding: const EdgeInsets.all(AppSpacing.sm),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: isDark ? 0.22 : 0.14),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                        ),
                        child: const AppGameIcon(
                          GameIcon.star,
                          size: 22,
                          fallbackColor: AppColors.purple,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
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
                          horizontal: AppSpacing.sm,
                          vertical: AppSpacing.xs,
                        ),
                        decoration: BoxDecoration(
                          color: context.status.warning.withValues(
                            alpha: isDark ? 0.22 : 0.16,
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: context.status.warning.withValues(
                              alpha: 0.4,
                            ),

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
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              '+${provider.xpEarned} XP',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isDark
                                        ? context.status.warning
                                        : AppColors.warningDark,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: provider.progress,
                      backgroundColor: isDark
                          ? AppColors.onGradient.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.outlineVariant,

                      valueColor: AlwaysStoppedAnimation<Color>(
                        provider.allCompleted
                            ? context.status.success
                            : AppColors.purple,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),

                  // Mini challenge list
                  ...provider.challenges.take(3).map((challenge) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
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
        const SizedBox(width: AppSpacing.sm),
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
            fallbackColor: context.status.success,
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
        return isDark ? context.status.warning : AppColors.warningDark;
      case 'voice':
        return AppColors.purpleLight;
      case 'social':
        return AppColors.teal;
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
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
class DailyChallengesSheet extends StatefulWidget {
  final DailyChallengesProvider provider;

  const DailyChallengesSheet({super.key, required this.provider});

  @override
  State<DailyChallengesSheet> createState() => _DailyChallengesSheetState();
}

class _DailyChallengesSheetState extends State<DailyChallengesSheet> {
  DailyChallengesProvider get provider => widget.provider;
  final Set<String> _claiming = {};
  String? _feedback;
  bool _feedbackIsError = false;

  void _showFeedback(String message, {required bool isError}) {
    if (!mounted) return;
    setState(() {
      _feedback = message;
      _feedbackIsError = isError;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: provider,
      builder: (context, _) => _buildSheet(context),
    );
  }

  Widget _buildSheet(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColors.purple;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.92,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.xl),
        ),
      ),
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: SafeArea(
        top: false,
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
                      ? AppColors.onGradient.withValues(alpha: 0.2)
                      : Theme.of(context).colorScheme.outlineVariant,

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
                const SizedBox(width: AppSpacing.md),
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
            if (_feedback != null) ...[
              const SizedBox(height: AppSpacing.md),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color:
                      (_feedbackIsError
                              ? Theme.of(context).colorScheme.error
                              : context.status.success)
                          .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Text(
                  _feedback!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 20),

            // Progress
            Row(
              children: [
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: LinearProgressIndicator(
                      value: provider.progress,
                      backgroundColor: isDark
                          ? AppColors.onGradient.withValues(alpha: 0.1)
                          : Theme.of(context).colorScheme.outlineVariant,

                      valueColor: AlwaysStoppedAnimation<Color>(
                        provider.allCompleted ? context.status.success : accent,
                      ),
                      minHeight: 12,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Text(
                  '${provider.completedCount}/${provider.totalChallenges}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Challenges list
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: provider.challenges.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: AppSpacing.md),
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
              const SizedBox(height: AppSpacing.lg),
              Container(
                padding: const EdgeInsets.all(AppSpacing.lg),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isDark
                        ? [
                            context.status.warning.withValues(alpha: 0.3),

                            AppColors.orange.withValues(alpha: 0.3),
                          ]
                        : AppColors.warmGradient
                              .map((c) => c.withValues(alpha: 0.22))
                              .toList(),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
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
                          ? context.status.warning
                          : AppColors.warningDark,
                    ),
                    const SizedBox(width: AppSpacing.md),
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
                                  ? context.status.warning
                                  : AppColors.deepOrange,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (provider.bonusClaimed)
                      const AppGameIcon(
                        GameIcon.checkmark,
                        size: 32,
                        fallbackColor: AppColors.greenSuccessBright,
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(
                          minHeight: 44,
                          minWidth: 44,
                        ),
                        child: FilledButton(
                          onPressed: provider.isLoading
                              ? null
                              : () => _claimBonus(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: context.status.success,

                            foregroundColor: AppColors.surfaceLight,
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            textStyle: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                          ),
                          child: Text('home.claimReward'.tr()),
                        ),
                      ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: AppSpacing.lg),
          ],
        ),
      ),
    );
  }

  Future<void> _claimBonus(BuildContext context) async {
    if (!_claiming.add('daily_bonus')) return;
    final bonusXp = provider.bonusXp;
    final levelProvider = context.read<LevelProvider>();
    final success = await provider.claimBonus();
    _claiming.remove('daily_bonus');
    if (success) {
      levelProvider.updateLevel(levelProvider.totalXp + bonusXp);
      _showFeedback('home.rewardClaimed'.tr(), isError: false);
      levelProvider.fetchLevelFull();
    } else {
      _showFeedback(
        provider.errorMessage ?? 'common.error'.tr(),
        isError: true,
      );
      provider.loadChallenges();
    }
  }

  Future<void> _claimReward(BuildContext context, String challengeId) async {
    if (!_claiming.add(challengeId)) return;
    final challenge = provider.challenges.firstWhere(
      (c) => c.id == challengeId,
    );
    final levelProvider = context.read<LevelProvider>();
    final success = await provider.claimReward(challengeId);
    _claiming.remove(challengeId);
    if (success) {
      // Optimistic so the header moves now; fetchLevelFull applies boosts.
      levelProvider.updateLevel(levelProvider.totalXp + challenge.xpReward);
      _showFeedback('home.rewardClaimed'.tr(), isError: false);
      levelProvider.fetchLevelFull();
    } else {
      _showFeedback(
        provider.errorMessage ?? 'common.error'.tr(),
        isError: true,
      );
      provider.loadChallenges();
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
        ? context.status.success.withValues(alpha: 0.12)
        : AppColors.greenSuccessBg;
    final defaultBg = Theme.of(context).colorScheme.surface;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: challenge.isCompleted ? completedBg : defaultBg,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: isDark
            ? const []
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 4),
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
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Center(
              child: AppGameIcon(
                _getCategoryIcon(challenge.category),
                size: 26,
                fallbackColor: categoryColor,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),

          // Content
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(),
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                    decoration: challenge.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  _description(),
                  style: theme.textTheme.bodySmall?.copyWith(color: textMuted),
                ),
                const SizedBox(height: AppSpacing.sm),
                // Progress bar
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: challenge.progress,
                          backgroundColor: isDark
                              ? AppColors.onGradient.withValues(alpha: 0.1)
                              : Theme.of(context).colorScheme.outlineVariant
                                    .withValues(alpha: 0.6),

                          valueColor: AlwaysStoppedAnimation<Color>(
                            challenge.isCompleted
                                ? context.status.success
                                : categoryColor,
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
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
          const SizedBox(width: AppSpacing.md),

          // Reward/Status
          Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: context.status.warning.withValues(
                    alpha: isDark ? 0.22 : 0.16,
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppGameIcon(
                      GameIcon.star,
                      size: 12,
                      fallbackColor: isDark
                          ? context.status.warning
                          : AppColors.warningDark,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${challenge.xpReward}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? context.status.warning
                            : AppColors.warningDark,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
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
                    child: FilledButton(
                      onPressed: onClaim,
                      style: FilledButton.styleFrom(
                        backgroundColor: context.status.success,

                        foregroundColor: AppColors.surfaceLight,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        textStyle: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md),
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

  String _title() {
    final key = 'home.challengeTexts.${challenge.id}.title';
    final text = key.tr();
    return text == key ? challenge.title : text;
  }

  String _description() {
    final key = 'home.challengeTexts.${challenge.id}.description';
    final text = key.tr(namedArgs: {'target': '${challenge.target}'});
    return text == key ? challenge.description : text;
  }

  Color _getCategoryColor(String category, {bool isDark = false}) {
    switch (category) {
      case 'time':
        return AppColors.teal;
      case 'content':
        return AppColors.purpleLight;
      case 'lesson':
        return AppColorRoles.primary(isDark);
      case 'vocabulary':
        return AppColors.purple;
      case 'streak':
        return AppColors.deepOrange;
      case 'xp':
        return isDark ? AppColors.warning : AppColors.warningDark;
      case 'voice':
        return AppColors.purpleLight;
      case 'social':
        return AppColors.teal;
      default:
        return AppColors.grey500;
    }
  }

  GameIcon _getCategoryIcon(String category) {
    switch (category) {
      case 'time':
        return GameIcon.clock;
      case 'content':
        return switch (challenge.id) {
          'watch_youtube' => GameIcon.video,
          'listen_podcast' => GameIcon.headphones,
          'read_news' => GameIcon.newspaper,
          _ => GameIcon.book,
        };
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
