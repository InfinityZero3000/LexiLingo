import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/streak_provider.dart';
import '../../domain/entities/streak_entity.dart';

/// Helper function to get icon from streak identifier
IconData _getStreakIcon(String identifier) {
  switch (identifier) {
    case 'trophy':
      return Icons.emoji_events;
    case 'fire':
      return Icons.local_fire_department;
    case 'bolt':
      return Icons.bolt;
    case 'star':
      return Icons.star;
    case 'sparkles':
      return Icons.auto_awesome;
    default:
      return Icons.local_fire_department;
  }
}

/// Streak Display Widget
/// Shows current streak with fire animation
/// Clean Architecture: Presentation layer UI component
class StreakWidget extends StatelessWidget {
  final bool showDetails;
  final VoidCallback? onTap;

  const StreakWidget({super.key, this.showDetails = false, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Consumer<StreakProvider>(
      builder: (context, provider, child) {
        final streak = provider.streak;

        if (provider.isLoading && streak == null) {
          return const SizedBox(
            width: 40,
            height: 40,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }

        if (streak == null) {
          return const SizedBox.shrink();
        }

        return GestureDetector(
          onTap: onTap ?? () => _showStreakDetails(context, streak),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              gradient: _getStreakGradient(streak.currentStreak),
              borderRadius: BorderRadius.circular(20),
              boxShadow: streak.currentStreak > 0
                  ? [
                      BoxShadow(
                        color: Colors.orange.withValues(alpha: 0.3),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStreakIcon(streak.streakIcon),
                  color: Colors.white,
                  size: 18,
                ),
                const SizedBox(width: 4),
                Text(
                  '${streak.currentStreak}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                if (streak.streakAtRisk) ...[
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.warning_rounded,
                    color: Colors.yellow,
                    size: 16,
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  LinearGradient _getStreakGradient(int streak) {
    if (streak >= 100) {
      return const LinearGradient(
        colors: [Color(0xFFFF6B00), Color(0xFFFF0000)],
      );
    } else if (streak >= 30) {
      return const LinearGradient(
        colors: [Color(0xFFFF8C00), Color(0xFFFF4500)],
      );
    } else if (streak >= 7) {
      return const LinearGradient(
        colors: [Color(0xFFFFAA00), Color(0xFFFF6B00)],
      );
    } else if (streak >= 1) {
      return const LinearGradient(
        colors: [Color(0xFFFFCC00), Color(0xFFFF8C00)],
      );
    }
    return LinearGradient(colors: [Colors.grey.shade400, Colors.grey.shade500]);
  }

  void _showStreakDetails(BuildContext context, StreakEntity streak) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StreakDetailsSheet(streak: streak),
    );
  }
}

/// Streak Card for Home Screen
/// Larger card with more details
class StreakCard extends StatelessWidget {
  const StreakCard({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Consumer<StreakProvider>(
      builder: (context, provider, child) {
        final streak = provider.streak;

        if (streak == null) {
          return Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.local_fire_department, color: Colors.grey),
                  const SizedBox(width: 12),
                  const Text('Start your streak today!'),
                  const Spacer(),
                  if (provider.isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          );
        }

        return Card(
          child: InkWell(
            onTap: () => _showStreakDetails(context, streak),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Streak Fire Icon
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: streak.currentStreak > 0
                                ? [Colors.orange, Colors.deepOrange]
                                : [Colors.grey.shade300, Colors.grey.shade400],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _getStreakIcon(streak.streakIcon),
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Streak Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  '${streak.currentStreak} Day Streak',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (streak.streakAtRisk) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.orange.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'At Risk!',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: Colors.orange.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (streak.isActiveToday)
                                  Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                if (streak.isActiveToday)
                                  const SizedBox(width: 4),
                                Text(
                                  streak.isActiveToday
                                      ? 'Done for today!'
                                      : 'Practice now to keep your streak!',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: streak.isActiveToday
                                        ? Colors.green
                                        : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Best streak
                      Column(
                        children: [
                          Icon(
                            Icons.emoji_events,
                            color: Colors.amber,
                            size: 16,
                          ),
                          Text(
                            '${streak.longestStreak}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Best',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),

                  // Freeze count
                  if (streak.freezeCount > 0) ...[
                    const Divider(height: 24),
                    Row(
                      children: [
                        Icon(Icons.ac_unit, size: 16, color: Colors.cyan),
                        const SizedBox(width: 8),
                        Text(
                          '${streak.freezeCount} Streak Freeze${streak.freezeCount > 1 ? 's' : ''} available',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showStreakDetails(BuildContext context, StreakEntity streak) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StreakDetailsSheet(streak: streak),
    );
  }
}

/// Streak Details Bottom Sheet
class StreakDetailsSheet extends StatelessWidget {
  final StreakEntity streak;

  const StreakDetailsSheet({super.key, required this.streak});

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
        children: [
          // Handle bar
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Big streak display
          Icon(
            _getStreakIcon(streak.streakIcon),
            color: Colors.orange,
            size: 64,
          ),
          const SizedBox(height: 8),
          Text(
            '${streak.currentStreak} Day Streak',
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            streak.streakLevel,
            style: theme.textTheme.titleMedium?.copyWith(color: Colors.orange),
          ),

          const SizedBox(height: 32),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatIcon(
                context,
                Icons.emoji_events,
                '${streak.longestStreak}',
                'Best Streak',
              ),
              _buildStatIcon(
                context,
                Icons.calendar_today,
                '${streak.totalDaysActive}',
                'Total Days',
              ),
              _buildStatIcon(
                context,
                Icons.ac_unit,
                '${streak.freezeCount}',
                'Freezes',
              ),
            ],
          ),

          const SizedBox(height: 24),

          // Status message
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: streak.isActiveToday
                  ? Colors.green.shade50
                  : streak.streakAtRisk
                  ? Colors.orange.shade50
                  : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Icon(
                  streak.isActiveToday
                      ? Icons.check_circle
                      : streak.streakAtRisk
                      ? Icons.warning_rounded
                      : Icons.info_outline,
                  color: streak.isActiveToday
                      ? Colors.green
                      : streak.streakAtRisk
                      ? Colors.orange
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    streak.isActiveToday
                        ? "Great job! You've practiced today. 🎉"
                        : streak.streakAtRisk
                        ? 'Practice now to save your streak!'
                        : 'Keep learning to build your streak!',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Use freeze button (if at risk and has freezes)
          if (streak.streakAtRisk &&
              streak.freezeCount > 0 &&
              !streak.isActiveToday)
            Consumer<StreakProvider>(
              builder: (context, provider, child) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: provider.isLoading
                        ? null
                        : () async {
                            final success = await provider.useFreeze();
                            if (success && context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Streak freeze activated!'),
                                  backgroundColor: Colors.blue,
                                ),
                              );
                            }
                          },
                    icon: Icon(Icons.ac_unit, size: 18, color: Colors.cyan),
                    label: const Text('Use Streak Freeze'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                );
              },
            ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildStatIcon(
    BuildContext context,
    IconData icon,
    String value,
    String label,
  ) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 24, color: Colors.orange),
        const SizedBox(height: 4),
        Text(
          value,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
        ),
      ],
    );
  }
}

/// Compact streak badge for AppBar
class StreakBadge extends StatelessWidget {
  const StreakBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<StreakProvider>(
      builder: (context, provider, child) {
        if (!provider.hasStreak) {
          return const SizedBox.shrink();
        }

        final streak = provider.streak!;

        return Tooltip(
          message: '${streak.currentStreak} day streak',
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: streak.currentStreak > 0
                  ? Colors.orange.shade100
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStreakIcon(streak.streakIcon),
                  color: streak.currentStreak > 0
                      ? Colors.orange.shade800
                      : Colors.grey.shade600,
                  size: 14,
                ),
                const SizedBox(width: 2),
                Text(
                  '${streak.currentStreak}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: streak.currentStreak > 0
                        ? Colors.orange.shade800
                        : Colors.grey.shade600,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
