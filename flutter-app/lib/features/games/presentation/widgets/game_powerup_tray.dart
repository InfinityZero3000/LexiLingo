import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';

/// Horizontal tray of owned in-game power-ups (Time Freeze, Skip Token,
/// Magnifying Glass, Shield, ...) for a mini-game screen to consume mid-play.
///
/// Only power-ups the player actually owns (quantity > 0) are shown, filtered
/// to [availableTypes] — the subset of the 10 power-up `item_type`s that make
/// sense for that particular game. Tapping consumes one via
/// [GamificationProvider.useItemWithEffects] and, on success, calls [onUse]
/// with the item type and its effects payload so the screen can apply the
/// gameplay effect (e.g. add seconds to a timer).
class GamePowerUpTray extends StatelessWidget {
  final List<String> availableTypes;
  final void Function(String itemType, Map<String, dynamic> effects) onUse;
  final bool enabled;

  const GamePowerUpTray({
    super.key,
    required this.availableTypes,
    required this.onUse,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<GamificationProvider>(
      builder: (context, provider, _) {
        final entries = availableTypes
            .map((type) => (type: type, owned: provider.powerUpsOf(type)))
            .where((entry) => entry.owned.isNotEmpty)
            .toList();
        if (entries.isEmpty) return const SizedBox.shrink();

        return SizedBox(
          height: 52,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: entries.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final quantity = entry.owned.fold<int>(
                0,
                (sum, inv) => sum + inv.quantity,
              );
              return _PowerUpButton(
                itemType: entry.type,
                inventoryId: entry.owned.first.id,
                itemName: entry.owned.first.item.name,
                quantity: quantity,
                enabled: enabled,
                onUsed: onUse,
              );
            },
          ),
        );
      },
    );
  }
}

class _PowerUpButton extends StatefulWidget {
  final String itemType;
  final String inventoryId;
  final String itemName;
  final int quantity;
  final bool enabled;
  final void Function(String itemType, Map<String, dynamic> effects) onUsed;

  const _PowerUpButton({
    required this.itemType,
    required this.inventoryId,
    required this.itemName,
    required this.quantity,
    required this.enabled,
    required this.onUsed,
  });

  @override
  State<_PowerUpButton> createState() => _PowerUpButtonState();
}

class _PowerUpButtonState extends State<_PowerUpButton> {
  bool _isUsing = false;

  Future<void> _handleTap() async {
    if (_isUsing || !widget.enabled) return;
    setState(() => _isUsing = true);
    final effects = await context
        .read<GamificationProvider>()
        .useItemWithEffects(widget.inventoryId);
    if (!mounted) return;
    setState(() => _isUsing = false);
    if (effects != null) {
      widget.onUsed(widget.itemType, effects);
    }
  }

  @override
  Widget build(BuildContext context) {
    final icon = gamePowerUpIcons[widget.itemType];
    final canUse = widget.enabled && !_isUsing;

    return Opacity(
      opacity: canUse ? 1.0 : 0.5,
      child: Tooltip(
        message: widget.itemName,
        child: GestureDetector(
          onTap: canUse ? _handleTap : null,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.purple.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: AppColors.purple.withValues(alpha: 0.35),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Center(
                  child: _isUsing
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: AppColors.purple,
                          ),
                        )
                      : (icon != null
                          ? AppGameIcon(icon, size: 26)
                          : const Icon(Icons.bolt, size: 26)),
                ),
                Positioned(
                  right: -4,
                  top: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.purple,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${widget.quantity}',
                      style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Persistent pill shown while an "armed" power-up (one that waits for the
/// next relevant game event rather than applying instantly, e.g. Mistake
/// Shield or Lucky Clover) is still active, so the player knows it's primed.
class ActivePowerUpBadge extends StatelessWidget {
  final String itemType;
  final String label;

  const ActivePowerUpBadge({super.key, required this.itemType, required this.label});

  @override
  Widget build(BuildContext context) {
    final icon = gamePowerUpIcons[itemType];
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.purple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.purple.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) AppGameIcon(icon, size: 16),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.purple,
            ),
          ),
        ],
      ),
    );
  }
}
