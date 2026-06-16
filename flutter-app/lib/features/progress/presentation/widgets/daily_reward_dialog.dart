import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/progress/domain/entities/streak_entity.dart';

/// Shows the daily reward celebration dialog.
Future<Object?> showDailyRewardDialog(BuildContext context, StreakProvider streakProvider) {
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
        child: _DailyRewardDialogContent(
          streakProvider: streakProvider,
        ),
      );
    },
    transitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutBack,
      );
      return ScaleTransition(
        scale: curved,
        child: FadeTransition(
          opacity: animation,
          child: child,
        ),
      );
    },
  );
}

class _DailyRewardDialogContent extends StatefulWidget {
  final StreakProvider streakProvider;

  const _DailyRewardDialogContent({
    required this.streakProvider,
  });

  @override
  State<_DailyRewardDialogContent> createState() => _DailyRewardDialogContentState();
}

class _DailyRewardDialogContentState extends State<_DailyRewardDialogContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseController;
  bool _isClaiming = false;

  final List<int> _rewardsCycle = const [5, 10, 15, 20, 25, 30, 50];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
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
        title: 'gamification.dailyRewardClaimed'.tr(defaultValue: 'Daily Reward Claimed!'),
        message: 'gamification.gemsReceived'.tr(
          defaultValue: 'You received {gems} gems!',
          namedArgs: {'gems': '$gemsAwarded'},
        ),
        autoCloseDuration: const Duration(seconds: 3),
      );
    } else {
      setState(() {
        _isClaiming = false;
      });
      final errorMsg = widget.streakProvider.errorMessage ?? 'common.failed'.tr();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(errorMsg)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final streak = widget.streakProvider.streak ?? StreakEntity.empty();
    final currentStreak = streak.currentStreak;
    final dayIndex = (currentStreak > 0 ? (currentStreak - 1) : 0) % 7;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    
    final bgGradient = isDark 
        ? const [Color(0xFF132333), Color(0xFF0F1B26)] 
        : const [Colors.white, Color(0xFFF0F6FB)];
    final primaryColor = AppColorRoles.primary(isDark);
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
          color: isDark ? const Color(0xFF2E4154) : Colors.white,
          width: 2,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(26),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient StarBurst design decoration
            const Positioned(
              top: -60,
              child: IgnorePointer(
                child: LottieAnimationWidget(
                  animation: LottieAnimation.starBurst,
                  width: 320,
                  height: 320,
                  repeat: false,
                ),
              ),
            ),
            
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 12),
                  // Animated Gift Icon
                  AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      final scale = 1.0 + (_pulseController.value * 0.08);
                      return Transform.scale(
                        scale: scale,
                        child: Container(
                          width: 86,
                          height: 86,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: AppColors.warmGradient,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orange.withValues(alpha: 0.4),
                                blurRadius: 20,
                                spreadRadius: 2,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.redeem_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 24),
                  
                  // Title
                  Text(
                    'gamification.dailyStreakRewardAvailable'.tr(defaultValue: 'Daily Streak Reward!'),
                    textAlign: TextAlign.center,
                    style: textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : AppColors.textDark,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  
                  // Subtitle
                  Text(
                    'gamification.dailyStreakRewardSubtitle'.tr(
                      defaultValue: "You've kept your streak alive! Claim your daily reward now.",
                    ),
                    textAlign: TextAlign.center,
                    style: textTheme.bodyMedium?.copyWith(
                      color: isDark ? const Color(0xFFB5C8D8) : AppColors.textGrey,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  
                  // 7-day reward tracker horizontal list
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(7, (index) {
                        final isActive = index == dayIndex;
                        final isClaimed = index < dayIndex;
                        final isLocked = index > dayIndex;
                        final gems = _rewardsCycle[index];

                        return _buildRewardDayCard(
                          context: context,
                          dayNumber: index + 1,
                          gems: gems,
                          isActive: isActive,
                          isClaimed: isClaimed,
                          isLocked: isLocked,
                          isDark: isDark,
                          primaryColor: primaryColor,
                        );
                      }),
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // Action Button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isClaiming ? null : _claimReward,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(56),
                        backgroundColor: AppColors.orange,
                        foregroundColor: Colors.white,
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : Text(
                              'gamification.claimDailyRewardButton'.tr(defaultValue: 'Claim Gems'),
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
                    onPressed: _isClaiming ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: isDark ? Colors.white60 : AppColors.textGrey,
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
    required BuildContext context,
    required int dayNumber,
    required int gems,
    required bool isActive,
    required bool isClaimed,
    required bool isLocked,
    required bool isDark,
    required Color primaryColor,
  }) {
    Color cardBg;
    Border? border;
    double scale = 1.0;
    
    if (isActive) {
      cardBg = isDark ? const Color(0xFF384D63) : Colors.white;
      border = Border.all(color: AppColors.orange, width: 2.5);
      scale = 1.05;
    } else if (isClaimed) {
      cardBg = isDark ? const Color(0xFF1E2F40) : const Color(0xFFE2F0D9);
      border = Border.all(color: isDark ? const Color(0xFF2E4154) : const Color(0xFFAAD38D), width: 1);
    } else {
      // Locked
      cardBg = isDark ? const Color(0xFF172433).withValues(alpha: 0.6) : const Color(0xFFF1F5F9);
      border = Border.all(color: isDark ? const Color(0xFF243547) : const Color(0xFFE2E8F0), width: 1);
    }

    final card = Container(
      width: 44,
      padding: const EdgeInsets.symmetric(vertical: 10),
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
                      ? Colors.white60
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
              Icons.diamond_rounded,
              color: isActive
                  ? AppColors.purpleLight
                  : isDark
                      ? Colors.white24
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
                    ? (isDark ? Colors.white : AppColors.textDark)
                    : isDark
                        ? Colors.white30
                        : AppColors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: scale != 1.0
          ? Transform.scale(scale: scale, child: card)
          : card,
    );
  }
}
