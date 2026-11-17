import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:easy_localization/easy_localization.dart';

/// Horizontal bar displaying all currently active boosts with live countdown.
/// Returns [SizedBox.shrink] when there are no active boosts. A boost
/// disappears the moment its countdown reaches zero and the inventory is
/// refreshed in the background.
class ActiveBoostsBar extends StatefulWidget {
  const ActiveBoostsBar({super.key});

  @override
  State<ActiveBoostsBar> createState() => _ActiveBoostsBarState();
}

class _ActiveBoostsBarState extends State<ActiveBoostsBar> {
  Timer? _ticker;
  int _lastCount = 0;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(int count) {
    if (count > 0 && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (count == 0) {
      _ticker?.cancel();
      _ticker = null;
    }
    if (count < _lastCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.read<GamificationProvider>().loadInventory();
      });
    }
    _lastCount = count;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationProvider>(
      builder: (context, provider, _) {
        final boosts = provider.activeBoosts;
        _syncTicker(boosts.length);
        if (boosts.isEmpty) return const SizedBox.shrink();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'gamification.activeBoosts'.tr(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColorRoles.textMuted(
                    Theme.of(context).brightness == Brightness.dark,
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: boosts.map((boost) {
                    return Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
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

class _BoostPill extends StatelessWidget {
  final InventoryItemEntity boost;
  const _BoostPill({required this.boost});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectType = boost.item.effectType ?? '';
    final boostColor = _colorForEffect(effectType);
    final icon = _iconForEffect(effectType);
    final label = _labelForEffect(effectType);

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: boostColor.withValues(alpha: isDark ? 0.18 : 0.10),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: boostColor.withValues(alpha: 0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: boostColor),
          const SizedBox(width: AppSpacing.sm),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: boostColor,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            width: 1,
            height: 12,
            color: boostColor.withValues(alpha: 0.3),
          ),
          const SizedBox(width: AppSpacing.sm),
          Icon(
            Icons.timer_outlined,
            size: 12,
            color: boostColor.withValues(alpha: 0.8),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            _formatDuration(boost.remainingDuration ?? Duration.zero),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
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
    _ => boost.item.name,
  };
}
