import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';

/// Overlay shown for ~1.5s after a successful boost purchase.
/// Scales in the boost icon with a glow pulse effect.
class BoostPurchaseAnimation extends StatefulWidget {
  final ShopItemEntity item;
  final VoidCallback onComplete;

  const BoostPurchaseAnimation({
    super.key,
    required this.item,
    required this.onComplete,
  });

  static Future<void> show(
    BuildContext context, {
    required ShopItemEntity item,
    required VoidCallback onComplete,
  }) {
    HapticFeedback.heavyImpact();
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Boost',
      barrierColor: Colors.black.withValues(alpha: 0.45),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (ctx, anim, _, child) =>
          FadeTransition(opacity: anim, child: child),
      pageBuilder: (ctx, _, __) =>
          BoostPurchaseAnimation(item: item, onComplete: onComplete),
    );
  }

  @override
  State<BoostPurchaseAnimation> createState() => _BoostPurchaseAnimationState();
}

class _BoostPurchaseAnimationState extends State<BoostPurchaseAnimation>
    with TickerProviderStateMixin {
  late final AnimationController _scale;
  late final AnimationController _pulse;
  late final Animation<double> _scaleAnim;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();

    _scale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );

    _scaleAnim = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _scale, curve: Curves.elasticOut));
    _pulseAnim = Tween<double>(
      begin: 1.0,
      end: 1.12,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));

    _scale.forward().then((_) {
      if (mounted) _pulse.repeat(reverse: true);
    });

    Future.delayed(const Duration(milliseconds: 1600), () {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        widget.onComplete();
      }
    });
  }

  @override
  void dispose() {
    _scale.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectType = widget.item.effectType ?? '';
    final boostColor = _colorForEffect(effectType);
    final icon = _iconForEffect(effectType);

    return Material(
      color: Colors.transparent,
      child: Center(
        child: ScaleTransition(
          scale: _scaleAnim,
          child: AnimatedBuilder(
            animation: _pulseAnim,
            builder: (_, child) =>
                Transform.scale(scale: _pulseAnim.value, child: child),
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isDark
                    ? AppColors.surfaceDarkElevated
                    : AppColors.surfaceLight,
                boxShadow: [
                  BoxShadow(
                    color: boostColor.withValues(alpha: 0.5),
                    blurRadius: 60,
                    spreadRadius: 16,
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 56, color: boostColor),
                  const SizedBox(height: 8),
                  Text(
                    'Activated!',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: boostColor,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // 0xFF137FEC was a literal duplicate of AppColors.primary — same palette
  // as ActiveBoostsBar._colorForEffect, kept in sync.
  Color _colorForEffect(String effectType) => switch (effectType) {
    ShopItemEntity.effectDoubleXP => AppColors.orange,
    ShopItemEntity.effectStreakFreeze => AppColors.primary,
    ShopItemEntity.effectUnlimitedHearts => AppColors.errorBright,
    ShopItemEntity.effectHintRefill => AppColors.cefrC,
    _ => AppColors.cefrA,
  };

  IconData _iconForEffect(String effectType) => switch (effectType) {
    ShopItemEntity.effectDoubleXP => Icons.bolt_rounded,
    ShopItemEntity.effectStreakFreeze => Icons.ac_unit_rounded,
    ShopItemEntity.effectUnlimitedHearts => Icons.favorite_rounded,
    ShopItemEntity.effectHintRefill => Icons.lightbulb_rounded,
    _ => Icons.star_rounded,
  };
}
