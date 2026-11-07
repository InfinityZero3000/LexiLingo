import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart'
    show AnimatedSuccessDialog;
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';

/// Shows the daily reward celebration dialog.
Future<Object?> showDailyRewardDialog(
  BuildContext context,
  StreakProvider streakProvider,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: false,
    barrierLabel: 'daily_reward',
    barrierColor: Colors.black87,
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
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  final GlobalKey _activeCardKey = GlobalKey();
  bool _isClaiming = false;

  final List<int> _rewardsCycle = const [5, 10, 15, 20, 25, 30, 50];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
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

      // Dismiss dialog
      Navigator.of(context).pop();

      // Show success dialog celebration
      AnimatedSuccessDialog.show(
        context,
        title: 'gamification.dailyRewardClaimed'.tr(),
        message: 'gamification.gemsReceived'.tr(
          namedArgs: {'gems': '$gemsAwarded'},
        ),
        autoCloseDuration: const Duration(seconds: 3),
      );
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
    final canClaim = streak.isDailyRewardAvailable && !_isClaiming;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bgGradient = isDark
        ? const [Color(0xFF132333), Color(0xFF0F1B26)]
        : const [AppColors.surfaceLight, Color(0xFFF0F6FB)];
    final textTheme = Theme.of(context).textTheme;

    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: bgGradient,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(
          color: isDark ? const Color(0xFF2E4154) : AppColors.surfaceLight,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // Keep the celebration decoration local to the gift. The
                  // old full-size StarBurst left a large star frozen behind
                  // the icon after its one-shot animation completed.
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final pulse = Curves.easeInOut.transform(
                        _pulseController.value,
                      );
                      return Semantics(
                        label: 'Daily reward gift',
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
                                      border: Border.all(
                                        color: AppColors.surfaceLight
                                            .withValues(alpha: 0.7),
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: AppColors.orange.withValues(
                                            alpha: 0.28,
                                          ),
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
                  ),
                  const SizedBox(height: 14),

                  // Title
                  Text(
                    'gamification.dailyStreakRewardAvailable'.tr(),
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDark
                          ? AppColors.surfaceLight
                          : AppColors.textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Subtitle
                  Text(
                    'gamification.dailyStreakRewardSubtitle'.tr(),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? const Color(0xFFB5C8D8)
                          : AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 14),

                  // 7-day reward tracker horizontal list. The padding leaves
                  // room for the active card's scale, border and glow, which
                  // the scroll view would otherwise clip.
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(7, (index) {
                        final isActive = index == dayIndex;
                        final isClaimed = index < dayIndex;
                        final isLocked = index > dayIndex;
                        final gems = _rewardsCycle[index];

                        return _buildRewardDayCard(
                          dayNumber: index + 1,
                          gems: gems,
                          isActive: isActive,
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
                    child: ElevatedButton(
                      onPressed: canClaim ? _claimReward : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.orange,
                        foregroundColor: AppColors.surfaceLight,
                        elevation: 4,
                        shadowColor: AppColors.orange.withValues(alpha: 0.4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                      ),
                      child: _isClaiming
                          ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  AppColors.surfaceLight,
                                ),
                              ),
                            )
                          : Text(
                              'gamification.claimDailyRewardButton'.tr(),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Skip / Close text button
                  TextButton(
                    onPressed: _isClaiming
                        ? null
                        : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark
                          ? AppColors.surfaceLight.withValues(alpha: 0.6)
                          : AppColors.textGrey,
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
      cardBg = isDark ? const Color(0xFF384D63) : AppColors.surfaceLight;
      border = Border.all(color: AppColors.orange, width: 2.5);
      scale = 1.05;
    } else if (isClaimed) {
      cardBg = isDark ? const Color(0xFF1E2F40) : const Color(0xFFE2F0D9);
      border = Border.all(
        color: isDark ? const Color(0xFF2E4154) : const Color(0xFFAAD38D),
        width: 1,
      );
    } else {
      // Locked
      cardBg = isDark
          ? const Color(0xFF172433).withValues(alpha: 0.6)
          : const Color(0xFFF1F5F9);
      border = Border.all(
        color: isDark ? const Color(0xFF243547) : const Color(0xFFE2E8F0),
        width: 1,
      );
    }

    final card = Semantics(
      label: 'Day $dayNumber, $gems gems',
      value: isActive
          ? 'available today'
          : isClaimed
          ? 'claimed'
          : 'locked',
      child: Container(
        key: isActive ? _activeCardKey : null,
        width: 60,
        height: 66,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(14),
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
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isActive
                    ? AppColors.orange
                    : isDark
                    ? AppColors.surfaceLight.withValues(alpha: 0.6)
                    : AppColors.textGrey,
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
              const SizedBox(height: 4),
              Text(
                '+$gems',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: isActive
                      ? (isDark ? AppColors.surfaceLight : AppColors.textDark)
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
