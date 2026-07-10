import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/daily_challenge_entity.dart';
import '../providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
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

    return Consumer<DailyChallengesProvider>(
      builder: (context, provider, child) {
        if (provider.isLoading && provider.challenges.isEmpty) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  const LottieLoadingWidget.small(),
                  const SizedBox(height: 12),
                  Text(
                    'home.loadingChallenges'.tr(),
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          );
        }

        if (provider.challenges.isEmpty) {
          return const SizedBox.shrink();
        }

        return Card(
          child: InkWell(
            onTap: () => _showChallengesSheet(context, provider),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.star,
                          color: Colors.purple.shade700,
                          size: 16,
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
                                fontSize: 15,
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
                                color: Colors.grey,
                                fontSize: 11,
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
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 10,
                              color: Colors.amber.shade800,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              '+${provider.xpEarned} XP',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
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
                      backgroundColor: AppColors.grey200,
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
                      child: Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: InkWell(
                          onTap: () => _showChallengesSheet(context, provider),
                          borderRadius: BorderRadius.circular(4),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                            child: Text(
                              'home.viewAllChallenges'.tr(
                                namedArgs: {
                                  'count': '${provider.challenges.length}',
                                },
                              ),
                              style: TextStyle(
                                color: Colors.purple.shade600,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
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
    return Row(
      children: [
        Icon(
          _getCategoryIcon(challenge.category),
          size: 14,
          color: _getCategoryColor(challenge.category, isDark: isDark),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            challenge.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              decoration: challenge.isCompleted
                  ? TextDecoration.lineThrough
                  : null,
              color: challenge.isCompleted ? Colors.grey : null,
              fontSize: 13,
            ),
          ),
        ),
        if (challenge.isCompleted)
          Icon(Icons.check_circle, color: Colors.green.shade400, size: 16)
        else
          Text(
            '${challenge.current}/${challenge.target}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey, fontSize: 11),
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
        return AppColors.orange;
      case 'xp':
        return AppColors.warning;
      case 'voice':
        return Colors.pink;
      case 'social':
        return AppColors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'lesson':
        return Icons.school_rounded;
      case 'vocabulary':
        return Icons.library_books_rounded;
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'xp':
        return Icons.bolt_rounded;
      case 'voice':
        return Icons.mic_rounded;
      case 'social':
        return Icons.people_rounded;
      default:
        return Icons.star_rounded;
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

    return Container(
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
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
                color: AppColors.grey300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Icon(Icons.star, size: 28, color: AppColors.purple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.dailyChallenges'.tr(),
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'home.completeBonusXp'.tr(
                        namedArgs: {'xp': '${provider.bonusXp}'},
                      ),

                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.purple,
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
                    backgroundColor: AppColors.grey200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.allCompleted
                          ? AppColors.greenSuccessBright
                          : AppColors.purple,
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
              separatorBuilder: (_, __) => const SizedBox(height: 12),
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
                  colors: [Colors.amber.shade200, Colors.orange.shade200],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.emoji_events,
                    size: 32,
                    color: Colors.amber.shade800,
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
                          ),
                        ),
                        Text(
                          'home.bonusXpEarned'.tr(
                            namedArgs: {'xp': '${provider.bonusXp}'},
                          ),

                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.greenSuccessBright,
                    size: 32,
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
    final challenge = provider.challenges.firstWhere((c) => c.id == challengeId);
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: challenge.isCompleted ? Colors.green.shade50 : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: challenge.isCompleted
              ? Colors.green.shade200
              : AppColors.grey200,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: _getCategoryColor(
                challenge.category,
                isDark: isDark,
              ).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Icon(
                _getCategoryIcon(challenge.category),
                size: 24,
                color: _getCategoryColor(challenge.category, isDark: isDark),
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
                    decoration: challenge.isCompleted
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  challenge.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
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
                          backgroundColor: AppColors.grey200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            challenge.isCompleted
                                ? AppColors.greenSuccessBright
                                : _getCategoryColor(
                                    challenge.category,
                                    isDark: isDark,
                                  ),
                          ),
                          minHeight: 6,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${challenge.current}/${challenge.target}',
                      style: theme.textTheme.bodySmall,
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
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.star, size: 12, color: Colors.amber.shade800),
                    const SizedBox(width: 2),
                    Text(
                      '${challenge.xpReward}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.amber.shade800,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              if (challenge.isCompleted)
                if (isClaimed)
                  const Icon(
                    Icons.check_circle,
                    color: AppColors.greenSuccessBright,
                    size: 28,
                  )
                else
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: onClaim,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.greenSuccessBright,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 11),
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
        return AppColors.orange;
      case 'xp':
        return AppColors.warning;
      case 'voice':
        return Colors.pink;
      case 'social':
        return AppColors.teal;
      default:
        return Colors.grey;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'lesson':
        return Icons.school_rounded;
      case 'vocabulary':
        return Icons.library_books_rounded;
      case 'streak':
        return Icons.local_fire_department_rounded;
      case 'xp':
        return Icons.bolt_rounded;
      case 'voice':
        return Icons.mic_rounded;
      case 'social':
        return Icons.people_rounded;
      default:
        return Icons.star_rounded;
    }
  }
}
