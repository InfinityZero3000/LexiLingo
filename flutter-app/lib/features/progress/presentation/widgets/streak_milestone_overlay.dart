import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';

/// Full-screen overlay shown when a streak milestone is reached (7, 14, 30, 60, 100, 365 days).
class StreakMilestoneOverlay extends StatefulWidget {
  final int streakDays;
  final VoidCallback onDismiss;
  final Duration displayDuration;

  const StreakMilestoneOverlay({
    super.key,
    required this.streakDays,
    required this.onDismiss,
    this.displayDuration = const Duration(seconds: 4),
  });

  static Future<void> show(
    BuildContext context, {
    required int streakDays,
    required VoidCallback onDismiss,
  }) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Streak Milestone',
      barrierColor: Colors.black.withValues(alpha: 0.75),
      transitionDuration: const Duration(milliseconds: 350),
      transitionBuilder: (ctx, anim, _, child) => FadeTransition(
        opacity: anim,
        child: child,
      ),
      pageBuilder: (ctx, _, __) => StreakMilestoneOverlay(
        streakDays: streakDays,
        onDismiss: onDismiss,
      ),
    );
  }

  @override
  State<StreakMilestoneOverlay> createState() => _StreakMilestoneOverlayState();
}

class _StreakMilestoneOverlayState extends State<StreakMilestoneOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _number;
  late final AnimationController _badge;
  late final Animation<double> _numberScale;
  late final Animation<double> _badgeScale;
  late final Animation<double> _numberBounce;

  @override
  void initState() {
    super.initState();
    _number = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _badge = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _numberScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _number, curve: Curves.elasticOut),
    );
    _numberBounce = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _number, curve: Curves.bounceOut),
    );
    _badgeScale = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _badge, curve: Curves.elasticOut),
    );

    Future.delayed(const Duration(milliseconds: 150), () {
      if (mounted) _badge.forward();
    });
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) _number.forward();
    });
    Future.delayed(widget.displayDuration, () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _number.dispose();
    _badge.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const fireOrange = Color(0xFFFF6B35);
    final assetPath = _badgeAsset(widget.streakDays);

    return GestureDetector(
      onTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        widget.onDismiss();
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Background celebration
            const Positioned.fill(
              child: IgnorePointer(
                child: LottieAnimationWidget.starBurst(),
              ),
            ),

            // Content card
            ScaleTransition(
              scale: _badgeScale,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 36,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDarkElevated
                      : Colors.white,
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: fireOrange.withValues(alpha: 0.3),
                      blurRadius: 40,
                      spreadRadius: 8,
                    ),
                  ],
                  border: Border.all(
                    color: fireOrange.withValues(alpha: 0.35),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Fire emoji header
                    Text(
                      'Streak Milestone!',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: fireOrange,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Badge image
                    if (assetPath != null)
                      Image.asset(
                        assetPath,
                        width: 100,
                        height: 100,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => _FallbackFireIcon(
                          color: fireOrange,
                        ),
                      )
                    else
                      _FallbackFireIcon(color: fireOrange),

                    const SizedBox(height: 20),

                    // Streak number — big and bouncy
                    ScaleTransition(
                      scale: _numberBounce,
                      child: AnimatedBuilder(
                        animation: _numberScale,
                        builder: (_, __) => Transform.scale(
                          scale: _numberScale.value,
                          child: Text(
                            '${widget.streakDays}',
                            style: TextStyle(
                              fontSize: 72,
                              fontWeight: FontWeight.w900,
                              color: fireOrange,
                              height: 1.0,
                            ),
                          ),
                        ),
                      ),
                    ),
                    Text(
                      'days in a row',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColorRoles.textMuted(isDark),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Motivational copy
                    Text(
                      _milestoneMessage(widget.streakDays),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColorRoles.textPrimary(isDark),
                        height: 1.4,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Tap hint
                    Text(
                      'Tap anywhere to continue',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColorRoles.textMuted(isDark).withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String? _badgeAsset(int days) => switch (days) {
    7 => 'assets/badges/streak7.png',
    14 => 'assets/badges/streak14.png',
    30 => 'assets/badges/streak30.png',
    60 => 'assets/badges/streak30.png',
    90 => 'assets/badges/streak90.png',
    100 => 'assets/badges/streak90.png',
    365 => 'assets/badges/streak365.png',
    _ => null,
  };

  String _milestoneMessage(int days) => switch (days) {
    7 => 'One week strong! You\'re building a habit.',
    14 => 'Two weeks! Consistency is your superpower.',
    30 => 'A whole month! You\'re unstoppable.',
    60 => 'Two months! Your dedication is inspiring.',
    100 => '100 days! You\'re a LexiLingo legend.',
    365 => 'One FULL YEAR! You\'ve achieved the impossible.',
    _ => '$days days! Keep pushing forward!',
  };
}

class _FallbackFireIcon extends StatelessWidget {
  final Color color;
  const _FallbackFireIcon({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color.withValues(alpha: 0.12),
      ),
      child: Icon(
        Icons.local_fire_department_rounded,
        size: 60,
        color: color,
      ),
    );
  }
}
