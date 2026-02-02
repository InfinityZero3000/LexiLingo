import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/daily_challenge_entity.dart';
import '../providers/daily_challenges_provider.dart';

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
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    'Loading challenges...',
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
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.purple.shade100,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.star,
                          color: Colors.purple.shade700,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Daily Challenges',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${provider.completedCount}/${provider.totalChallenges} completed',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // XP earned
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.shade100,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              size: 12,
                              color: Colors.amber.shade800,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '+${provider.xpEarned} XP',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: Colors.amber.shade800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: provider.progress,
                      backgroundColor: Colors.grey.shade200,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        provider.allCompleted ? Colors.green : Colors.purple,
                      ),
                      minHeight: 8,
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Mini challenge list
                  ...provider.challenges.take(3).map((challenge) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _buildMiniChallenge(context, challenge, provider),
                    );
                  }),

                  // View all button
                  if (provider.challenges.length > 3)
                    Center(
                      child: TextButton(
                        onPressed: () =>
                            _showChallengesSheet(context, provider),
                        child: Text(
                          'View all ${provider.challenges.length} challenges',
                          style: TextStyle(color: Colors.purple.shade600),
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
    return Row(
      children: [
        Text(challenge.icon, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            challenge.title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              decoration: challenge.isCompleted
                  ? TextDecoration.lineThrough
                  : null,
              color: challenge.isCompleted ? Colors.grey : null,
            ),
          ),
        ),
        if (challenge.isCompleted)
          Icon(Icons.check_circle, color: Colors.green.shade400, size: 20)
        else
          Text(
            '${challenge.current}/${challenge.target}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: Colors.grey),
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
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Header
          Row(
            children: [
              Icon(Icons.star, size: 28, color: Colors.purple),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Challenges',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Complete all for bonus ${provider.bonusXp} XP!',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.purple,
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
                    backgroundColor: Colors.grey.shade200,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      provider.allCompleted ? Colors.green : Colors.purple,
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
                          'All Challenges Complete!',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          '+${provider.bonusXp} Bonus XP',
                          style: TextStyle(
                            color: Colors.orange.shade800,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.check_circle, color: Colors.green, size: 32),
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
    final success = await provider.claimReward(challengeId);
    if (success && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reward claimed successfully!'),
          backgroundColor: Colors.green,
        ),
      );
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

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: challenge.isCompleted ? Colors.green.shade50 : theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: challenge.isCompleted
              ? Colors.green.shade200
              : Colors.grey.shade200,
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
              ).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(challenge.icon, style: const TextStyle(fontSize: 24)),
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
                          backgroundColor: Colors.grey.shade200,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            challenge.isCompleted
                                ? Colors.green
                                : _getCategoryColor(challenge.category),
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
                  const Icon(Icons.check_circle, color: Colors.green, size: 28)
                else
                  SizedBox(
                    height: 28,
                    child: ElevatedButton(
                      onPressed: onClaim,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        textStyle: const TextStyle(fontSize: 11),
                      ),
                      child: const Text('Claim'),
                    ),
                  ),
            ],
          ),
        ],
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'lesson':
        return Colors.blue;
      case 'vocabulary':
        return Colors.purple;
      case 'streak':
        return Colors.orange;
      case 'xp':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }
}
