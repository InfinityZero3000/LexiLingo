import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import '../providers/streak_provider.dart';
import '../../domain/entities/streak_entity.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

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
            child: LottieLoadingWidget.small(),
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
              boxShadow: streak.currentStreak >= 3
                  ? [
                      BoxShadow(
                        color: AppColors.orange.withValues(alpha: 0.45),
                        blurRadius: 10,
                        spreadRadius: 1,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (streak.streakAtRisk)
                  LottieAnimationWidget.heartbeat(width: 22, height: 22)
                else
                  Icon(
                    _getStreakIcon(streak.streakIcon),
                    color: Theme.of(context).colorScheme.surface,
                    size: 18,
                  ),
                const SizedBox(width: 4),
                Text(
                  '${streak.currentStreak}',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.surface,
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
    return LinearGradient(colors: [AppColors.grey400, AppColors.grey500]);
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
                  Text('home.startStreakToday'.tr()),
                  const Spacer(),
                  if (provider.isLoading)
                    const LottieAnimationWidget.pulse(width: 24, height: 24),
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
                                ? [AppColors.orange, AppColors.deepOrange]
                                : [AppColors.grey300, AppColors.grey400],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: streak.streakAtRisk
                            ? LottieAnimationWidget.heartbeat(
                                width: 32,
                                height: 32,
                              )
                            : Icon(
                                _getStreakIcon(streak.streakIcon),
                                color: Theme.of(context).colorScheme.surface,
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
                                  'home.dayStreakCount'.tr(
                                    namedArgs: {
                                      'count': '${streak.currentStreak}',
                                    },
                                  ),
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
                                      'home.streakAtRisk'.tr(),
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
                                    color: AppColors.greenSuccessBright,
                                  ),
                                if (streak.isActiveToday)
                                  const SizedBox(width: 4),
                                Text(
                                  streak.isActiveToday
                                      ? 'home.doneForToday'.tr()
                                      : 'home.practiceToKeepStreak'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: streak.isActiveToday
                                        ? AppColors.greenSuccessBright
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
                            color: AppColors.warning,
                            size: 16,
                          ),
                          Text(
                            '${streak.longestStreak}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'home.streakBestLabel'.tr(),
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
                          'home.streakFreezesAvailable'.tr(
                            namedArgs: {'count': '${streak.freezeCount}'},
                          ),
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
              color: AppColors.grey300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 24),

          // Big streak display
          if (streak.currentStreak >= 7)
            LargeStreakFireWidget(
              icon: _getStreakIcon(streak.streakIcon),
              size: 64,
            )
          else
            Icon(
              _getStreakIcon(streak.streakIcon),
              color: AppColors.orange,
              size: 64,
            ),
          const SizedBox(height: 12),
          Text(
            'home.dayStreakCount'.tr(
              namedArgs: {'count': '${streak.currentStreak}'},
            ),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            streak.streakLevel,
            style: theme.textTheme.titleMedium?.copyWith(
              color: AppColors.orange,
            ),
          ),

          const SizedBox(height: 16),
          // Restores remaining count display
          Text(
            'Lượt khôi phục chuỗi còn lại trong tháng: ${streak.restoresRemaining}',
            style: theme.textTheme.bodySmall?.copyWith(color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildStatIcon(
                context,
                Icons.emoji_events,
                '${streak.longestStreak}',
                'home.bestStreak'.tr(),
              ),
              _buildStatIcon(
                context,
                Icons.calendar_today,
                '${streak.totalDaysActive}',
                'home.totalDays'.tr(),
              ),
              _buildStatIcon(
                context,
                Icons.ac_unit,
                '${streak.freezeCount}',
                'home.freezes'.tr(),
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
                  : AppColors.grey100,
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
                      ? AppColors.greenSuccessBright
                      : streak.streakAtRisk
                      ? AppColors.orange
                      : Colors.grey,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    streak.isActiveToday
                        ? 'home.practicedToday'.tr()
                        : streak.streakAtRisk
                        ? 'home.practiceToSaveStreak'.tr()
                        : 'home.keepLearningStreak'.tr(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: streak.isActiveToday
                          ? Colors.green.shade800
                          : streak.streakAtRisk
                          ? Colors.orange.shade800
                          : Colors.grey.shade700,
                    ),
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
                              final isDark =
                                  Theme.of(context).brightness ==
                                  Brightness.dark;
                              final accent = AppColorRoles.primary(isDark);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'home.streakFreezeActivated'.tr(),
                                  ),
                                  backgroundColor: accent,
                                ),
                              );
                            }
                          },
                    icon: Icon(Icons.ac_unit, size: 18, color: Colors.cyan),
                    label: Text('home.useStreakFreeze'.tr()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColorRoles.primary(
                        Theme.of(context).brightness == Brightness.dark,
                      ),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                );
              },
            ),

          // Restore streak section
          if (streak.canRestore) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bạn có thể khôi phục lại chuỗi ${streak.previousStreak} ngày cũ! Bạn còn ${streak.restoresRemaining} lượt khôi phục trong tháng này.',
                      style: TextStyle(color: Colors.blue.shade800, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Consumer<StreakProvider>(
              builder: (context, provider, child) {
                return SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: provider.isLoading
                        ? null
                        : () async {
                            final success = await provider.restoreStreak();
                            if (success && context.mounted) {
                              Navigator.pop(context);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Đã khôi phục chuỗi thành công!',
                                  ),
                                  backgroundColor: Colors.green,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.healing, color: Colors.white),
                    label: Text('Khôi phục chuỗi (${streak.previousStreak} ngày)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                );
              },
            ),
          ],

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
        Icon(icon, size: 24, color: AppColors.orange),
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

class LargeStreakFireWidget extends StatefulWidget {
  final IconData icon;
  final double size;

  const LargeStreakFireWidget({
    super.key,
    required this.icon,
    this.size = 64,
  });

  @override
  State<LargeStreakFireWidget> createState() => _LargeStreakFireWidgetState();
}

class _LargeStreakFireWidgetState extends State<LargeStreakFireWidget>
    with TickerProviderStateMixin {
  late final AnimationController _rotateController;
  late final AnimationController _pulseController;
  late final Animation<double> _rotation;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _rotateController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
    
    _rotation = Tween<double>(begin: -0.04, end: 0.04).animate(
      CurvedAnimation(parent: _rotateController, curve: Curves.easeInOut),
    );

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);

    _scale = Tween<double>(begin: 0.96, end: 1.04).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    _glow = Tween<double>(begin: 4.0, end: 16.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _rotateController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_rotateController, _pulseController]),
      builder: (context, child) {
        return Transform.scale(
          scale: _scale.value,
          child: RotationTransition(
            turns: _rotation,
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.orange.withOpacity(0.4),
                    blurRadius: _glow.value * 2,
                    spreadRadius: _glow.value / 2,
                  ),
                  BoxShadow(
                    color: Colors.red.withOpacity(0.2),
                    blurRadius: _glow.value * 3,
                    spreadRadius: _glow.value,
                  ),
                ],
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                ),
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Colors.orange, Colors.redAccent],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ).createShader(bounds),
                  child: Icon(
                    widget.icon,
                    color: Colors.white,
                    size: widget.size,
                  ),
                ),
              ),
            ),
          ),
        );
      },
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
          message: 'home.dayStreakCount'.tr(
            namedArgs: {'count': '${streak.currentStreak}'},
          ),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: streak.currentStreak > 0
                  ? Colors.orange.shade100
                  : AppColors.grey200,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _getStreakIcon(streak.streakIcon),
                  color: streak.currentStreak > 0
                      ? Colors.orange.shade800
                      : AppColors.grey600,
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
                        : AppColors.grey600,
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
