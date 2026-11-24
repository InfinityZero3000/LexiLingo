import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/progress/presentation/theme/progress_palette.dart';

/// Shows the daily reward celebration dialog.
Future<Object?> showDailyRewardDialog(
  BuildContext context,
  StreakProvider streakProvider,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'daily_reward',
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.87),
    transitionDuration: const Duration(milliseconds: 350),
    pageBuilder: (context, animation, secondaryAnimation) {
      return Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: _DailyRewardDialogContent(streakProvider: streakProvider),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return ScaleTransition(
        scale: curved,
        child: FadeTransition(opacity: animation, child: child),
      );
    },
  );
}

class _DailyRewardDialogContent extends StatefulWidget {
  final StreakProvider streakProvider;

  const _DailyRewardDialogContent({required this.streakProvider});

  @override
  State<_DailyRewardDialogContent> createState() =>
      _DailyRewardDialogContentState();
}

class _DailyRewardDialogContentState extends State<_DailyRewardDialogContent>
    with TickerProviderStateMixin {
  late final AnimationController _pulseController;
  late final AnimationController _burstController;
  final GlobalKey _activeCardKey = GlobalKey();
  bool _isClaiming = false;
  int? _claimedGems;

  final List<int> _rewardsCycle = const [5, 10, 15, 20, 25, 30, 50];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
    _burstController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _activeCardKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _burstController.dispose();
    super.dispose();
  }

  Future<void> _claimReward() async {
    if (_isClaiming) return;
    setState(() {
      _isClaiming = true;
    });

    final data = await widget.streakProvider.claimDailyReward();

    if (!mounted) return;

    if (data != null) {
      final int gemsAwarded = data['gems_awarded'] ?? 0;

      // Reload wallet to sync gems count on UI
      context.read<GamificationProvider>().loadWallet();

      setState(() {
        _isClaiming = false;
        _claimedGems = gemsAwarded;
      });
      _pulseController.stop();
      _burstController.forward(from: 0);
    } else {
      setState(() {
        _isClaiming = false;
      });
      final errorMsg =
          widget.streakProvider.errorMessage ?? 'common.failed'.tr();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(errorMsg)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.streakProvider.streak ?? StreakEntity.empty();
    final currentStreak = streak.currentStreak;
    final dayIndex = (currentStreak > 0 ? (currentStreak - 1) : 0) % 7;
    final claimed = _claimedGems != null;
    final canClaim = streak.isDailyRewardAvailable && !_isClaiming;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgGradient = isDark
        ? const [ProgressPalette.nightTop, ProgressPalette.nightBottom]
        : const [AppColors.surfaceLight, ProgressPalette.mist];
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bgGradient,
        ),
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: Theme.of(
              context,
            ).colorScheme.shadow.withValues(alpha: isDark ? 0.5 : 0.15),

            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: 28,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: AppSpacing.md),
                  // Keep the celebration decoration local to the gift. The
                  // old full-size StarBurst left a large star frozen behind
                  // the icon after its one-shot animation completed.
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 300),
                    child: claimed
                        ? _GemBurst(
                            key: const ValueKey('daily-reward-gem-burst'),
                            controller: _burstController,
                          )
                        : _buildGiftEmblem(),
                  ),
                  const SizedBox(height: 14),

                  // Title
                  _swap(
                    Text(
                      claimed
                          ? 'gamification.dailyRewardClaimed'.tr()
                          : 'gamification.dailyStreakRewardAvailable'.tr(),
                      key: ValueKey('title-$claimed'),
                      textAlign: TextAlign.center,
                      style: textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: isDark
                            ? AppColors.surfaceLight
                            : Theme.of(context).colorScheme.onSurface,

                        letterSpacing: -0.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),

                  // Subtitle
                  _swap(
                    Text(
                      claimed
                          ? 'gamification.gemsReceived'.tr(
                              namedArgs: {'gems': '$_claimedGems'},
                            )
                          : 'gamification.dailyStreakRewardSubtitle'.tr(),
                      key: ValueKey('subtitle-$claimed'),
                      textAlign: TextAlign.center,
                      style: textTheme.bodyMedium?.copyWith(
                        color: claimed
                            ? AppColors.purpleLight
                            : isDark
                            ? ProgressPalette.nightText
                            : Theme.of(context).colorScheme.onSurfaceVariant,

                        fontWeight: claimed ? FontWeight.w800 : null,
                        height: 1.4,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 7-day reward tracker horizontal list. The padding leaves
                  // room for the active card's scale, border and glow, which
                  // the scroll view would otherwise clip.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(7, (index) {
                        final isActive = index == dayIndex;
                        final isClaimed =
                            index < dayIndex || (claimed && index == dayIndex);
                        final isLocked = index > dayIndex;
                        final gems = _rewardsCycle[index];

                        return _buildRewardDayCard(
                          dayNumber: index + 1,
                          gems: gems,
                          isActive: isActive && !claimed,
                          isClaimed: isClaimed,
                          isLocked: isLocked,
                          isDark: isDark,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: claimed
                          ? () => Navigator.of(context).pop()
                          : canClaim
                          ? _claimReward
                          : null,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.orange,
                        foregroundColor: AppColors.surfaceLight,
                        elevation: 4,
                        shadowColor: AppColors.orange.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.mdAll,
                        ),
                      ),
                      child: _isClaiming
                          ? const SizedBox(
                              width: 24,
                              height: AppSpacing.xl,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.surfaceLight,
                                ),
                              ),
                            )
                          : Text(
                              claimed
                                  ? 'common.awesome'.tr()
                                  : 'gamification.claimDailyRewardButton'.tr(),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                            ),
                    ),
                  ),
                  if (!claimed) const SizedBox(height: AppSpacing.md),

                  // Skip / Close text button
                  if (!claimed)
                    TextButton(
                      onPressed: _isClaiming
                          ? null
                          : () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: isDark
                            ? AppColors.surfaceLight.withValues(alpha: 0.6)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      child: Text('common.close'.tr()),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _swap(Widget child) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 260),
    transitionBuilder: (c, a) => FadeTransition(
      opacity: a,
      child: SlideTransition(
        position: Tween(
          begin: const Offset(0, 0.25),
          end: Offset.zero,
        ).animate(a),
        child: c,
      ),
    ),
    child: child,
  );

  Widget _buildGiftEmblem() {
    return AnimatedBuilder(
      key: const ValueKey('daily-reward-gift'),
      animation: _pulseController,
      builder: (context, child) {
        final pulse = Curves.easeInOut.transform(_pulseController.value);
        return Semantics(
          label: 'gamification.dailyReward.giftLabel'.tr(),
          image: true,
          child: SizedBox(
            key: const ValueKey('daily-reward-gift-emblem'),
            width: 124,
            height: 112,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Transform.scale(
                  scale: 0.94 + (pulse * 0.08),
                  child: Container(
                    width: 112,
                    height: 112,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(
                        colors: [
                          AppColors.orange.withValues(
                            alpha: 0.22 - (pulse * 0.06),
                          ),
                          AppColors.orange.withValues(alpha: 0),
                        ],
                      ),
                    ),
                  ),
                ),
                Transform.translate(
                  offset: Offset(0, 1.5 - (pulse * 3)),
                  child: Transform.scale(
                    scale: 1 + (pulse * 0.025),
                    child: Container(
                      width: 86,
                      height: 86,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: AppColors.warmGradient,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.orange.withValues(alpha: 0.28),
                            blurRadius: 18,
                            spreadRadius: 1,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.redeem_rounded,
                        color: AppColors.surfaceLight,
                        size: 46,
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 15 + (pulse * 2),
                  right: 10,
                  child: _RewardSparkle(
                    size: 8,
                    opacity: 0.55 + (pulse * 0.35),
                  ),
                ),
                Positioned(
                  bottom: 19 - (pulse * 2),
                  left: 13,
                  child: _RewardSparkle(
                    size: 6,
                    opacity: 0.45 + ((1 - pulse) * 0.35),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildRewardDayCard({
    required int dayNumber,
    required int gems,
    required bool isActive,
    required bool isClaimed,
    required bool isLocked,
    required bool isDark,
  }) {
    Color cardBg;
    Border? border;
    double scale = 1.0;

    if (isActive) {
      cardBg = isDark
          ? ProgressPalette.nightCardRaised
          : AppColors.surfaceLight;
      border = Border.all(color: AppColors.orange, width: 2.5);
      scale = 1.05;
    } else if (isClaimed) {
      cardBg = isDark ? ProgressPalette.doneNight : ProgressPalette.doneLight;
    } else {
      // Locked
      cardBg = isDark
          ? ProgressPalette.todayNight.withValues(alpha: 0.6)
          : ProgressPalette.todayLight;
    }

    final card = Semantics(
      label: 'gamification.dailyReward.dayLabel'.tr(
        namedArgs: {'day': '$dayNumber', 'gems': '$gems'},
      ),
      value: isActive
          ? 'gamification.dailyReward.availableToday'.tr()
          : isClaimed
          ? 'gamification.dailyReward.claimed'.tr()
          : 'gamification.dailyReward.locked'.tr(),
      child: Container(
        key: isActive ? _activeCardKey : null,
        width: 60,
        height: 66,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: border,
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: AppColors.orange.withValues(alpha: 0.3),
                    blurRadius: 10,
                    spreadRadius: 1,
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'D$dayNumber',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: isActive
                    ? AppColors.orange
                    : isDark
                    ? AppColors.surfaceLight.withValues(alpha: 0.6)
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 6),
            if (isClaimed)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenSuccessBright,
                size: 18,
              )
            else ...[
              Icon(
                isLocked ? Icons.lock_rounded : Icons.diamond_rounded,
                color: isActive
                    ? AppColors.purpleLight
                    : isDark
                    ? AppColors.surfaceLight.withValues(alpha: 0.24)
                    : AppColors.textMuted,
                size: 16,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                '+$gems',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: isActive
                      ? (isDark
                            ? AppColors.surfaceLight
                            : Theme.of(context).colorScheme.onSurface)
                      : isDark
                      ? AppColors.surfaceLight.withValues(alpha: 0.3)
                      : AppColors.textMuted,
                ),
              ),
            ],
          ],
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 3),
      child: scale != 1.0 ? Transform.scale(scale: scale, child: card) : card,
    );
  }
}

class _RewardSparkle extends StatelessWidget {
  const _RewardSparkle({required this.size, required this.opacity});

  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: AppColors.orange,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _GemBurst extends StatelessWidget {
  const _GemBurst({super.key, required this.controller});

  final AnimationController controller;

  static const _shards = 8;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'gamification.dailyReward.gemsReceived'.tr(),
      image: true,
      child: SizedBox(
        width: 124,
        height: 112,
        child: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final t = controller.value;
            final pop = Curves.elasticOut.transform(math.min(1, t * 1.4));
            final fly = Curves.easeOutCubic.transform(t);
            return Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < _shards; i++)
                  Transform.translate(
                    offset: Offset.fromDirection(
                      (math.pi * 2 / _shards) * i - math.pi / 2,
                      18 + fly * 52,
                    ),
                    child: Opacity(
                      opacity: (1 - t).clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 0.6 + (1 - t) * 0.5,
                        child: Icon(
                          Icons.diamond_rounded,
                          size: i.isEven ? 14 : 10,
                          color: i.isEven
                              ? AppColors.purpleLight
                              : AppColors.orange,
                        ),
                      ),
                    ),
                  ),
                Transform.scale(
                  scale: pop,
                  child: Container(
                    width: 86,
                    height: 86,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: AppColors.purpleGradient,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.purpleLight.withValues(alpha: 0.4),
                          blurRadius: 20,
                          spreadRadius: 1,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.diamond_rounded,
                      color: AppColors.surfaceLight,
                      size: 44,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
