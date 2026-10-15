import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:easy_localization/easy_localization.dart';

/// Horizontal bar displaying all currently active boosts with live countdown.
/// Returns [SizedBox.shrink] when there are no active boosts.
class ActiveBoostsBar extends StatelessWidget {
  const ActiveBoostsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationProvider>(
      builder: (context, provider, _) {
        final boosts = provider.activeBoosts;
        if (boosts.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'gamification.activeBoosts'.tr(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColorRoles.textMuted(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: boosts.map((boost) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _BoostPill(boost: boost),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _BoostPill extends StatefulWidget {
  final InventoryItemEntity boost;
  const _BoostPill({required this.boost});

  @override
  State<_BoostPill> createState() => _BoostPillState();
}

class _BoostPillState extends State<_BoostPill> {
  late Timer _timer;
  late Duration _remaining;

  @override
  void initState() {
    super.initState();
    _remaining = widget.boost.remainingDuration ?? Duration.zero;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final r = widget.boost.remainingDuration ?? Duration.zero;
      setState(() => _remaining = r);
      if (_remaining == Duration.zero) _timer.cancel();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectType = widget.boost.item.effectType ?? '';
    final boostColor = _colorForEffect(effectType);
    final icon = _iconForEffect(effectType);
    final label = _labelForEffect(effectType);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: boostColor.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: boostColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: boostColor),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: boostColor,
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1,
            height: 12,
            color: boostColor.withValues(alpha: 0.3),
          ),
          const SizedBox(width: 6),
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: boostColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: 3),
          Text(
            _formatDuration(_remaining),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: boostColor.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(Duration d) {
    if (d.inHours >= 1) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m}m';
    }
    final m = d.inMinutes;
    final s = d.inSeconds.remainder(60);
    return '${m}m ${s}s';
  }

  // 0xFF137FEC was a literal duplicate of AppColors.primary.
  Color _colorForEffect(String effectType) => switch (effectType) {
    ShopItemEntity.effectDoubleXP => AppColors.orange,
    ShopItemEntity.effectStreakFreeze => AppColors.primary,
    ShopItemEntity.effectUnlimitedHearts => AppColors.errorBright,
    ShopItemEntity.effectHintRefill => AppColors.cefrC,
    _ => AppColors.grey500,
  };

  IconData _iconForEffect(String effectType) => switch (effectType) {
    ShopItemEntity.effectDoubleXP => Icons.bolt_rounded,
    ShopItemEntity.effectStreakFreeze => Icons.ac_unit_rounded,
    ShopItemEntity.effectUnlimitedHearts => Icons.favorite_rounded,
    ShopItemEntity.effectHintRefill => Icons.lightbulb_rounded,
    _ => Icons.star_rounded,
  };

  String _labelForEffect(String effectType) => switch (effectType) {
    ShopItemEntity.effectDoubleXP => '2× XP',
    ShopItemEntity.effectStreakFreeze => 'Freeze',
    ShopItemEntity.effectUnlimitedHearts => '∞ Hearts',
    ShopItemEntity.effectHintRefill => 'Hints',
    _ => widget.boost.item.name,
  };
}
