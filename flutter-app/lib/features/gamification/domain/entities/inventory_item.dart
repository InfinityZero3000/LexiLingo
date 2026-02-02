import 'package:equatable/equatable.dart';
import 'shop_item.dart';

/// Inventory Item Entity
class InventoryItemEntity extends Equatable {
  final String id;
  final ShopItemEntity item;
  final int quantity;
  final bool isActive;
  final DateTime? activatedAt;
  final DateTime? expiresAt;
  final DateTime purchasedAt;

  const InventoryItemEntity({
    required this.id,
    required this.item,
    required this.quantity,
    this.isActive = false,
    this.activatedAt,
    this.expiresAt,
    required this.purchasedAt,
  });

  bool get isExpired =>
      expiresAt != null && DateTime.now().isAfter(expiresAt!);

  bool get canUse => quantity > 0 && !isExpired && !isActive;

  Duration? get remainingDuration {
    if (expiresAt == null || !isActive) return null;
    final remaining = expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  factory InventoryItemEntity.fromJson(Map<String, dynamic> json) {
    return InventoryItemEntity(
      id: json['id'] ?? '',
      item: ShopItemEntity.fromJson(json['item'] ?? {}),
      quantity: json['quantity'] ?? 0,
      isActive: json['is_active'] ?? json['isActive'] ?? false,
      activatedAt: json['activated_at'] != null
          ? DateTime.parse(json['activated_at'])
          : null,
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'])
          : null,
      purchasedAt: json['purchased_at'] != null
          ? DateTime.parse(json['purchased_at'])
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, item.id, quantity, isActive];
}
