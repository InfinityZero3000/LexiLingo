import 'package:equatable/equatable.dart';

/// Shop Item Entity
class ShopItemEntity extends Equatable {
  final String id;
  final String name;
  final String description;
  final String category;
  final int priceGems;
  final String iconUrl;
  final String? effectType;
  final int? effectDuration; // in hours
  final bool isAvailable;
  final int? stockLimit;
  final int? stockRemaining;

  const ShopItemEntity({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.priceGems,
    required this.iconUrl,
    this.effectType,
    this.effectDuration,
    this.isAvailable = true,
    this.stockLimit,
    this.stockRemaining,
  });

  /// Category types
  static const String categoryPowerUps = 'power_ups';
  static const String categoryCosmetics = 'cosmetics';
  static const String categoryBoosts = 'boosts';
  static const String categorySpecial = 'special';

  /// Effect types
  static const String effectStreakFreeze = 'streak_freeze';
  static const String effectDoubleXP = 'double_xp';
  static const String effectUnlimitedHearts = 'unlimited_hearts';
  static const String effectHintRefill = 'hint_refill';

  bool get isPowerUp => category == categoryPowerUps;
  bool get isCosmetic => category == categoryCosmetics;
  bool get isBoost => category == categoryBoosts;
  bool get isLimitedStock => stockLimit != null && stockLimit! > 0;
  bool get isOutOfStock => isLimitedStock && (stockRemaining ?? 0) <= 0;

  factory ShopItemEntity.fromJson(Map<String, dynamic> json) {
    return ShopItemEntity(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: json['category'] ?? categoryPowerUps,
      priceGems: json['price_gems'] ?? json['priceGems'] ?? 0,
      iconUrl: json['icon_url'] ?? json['iconUrl'] ?? '',
      effectType: json['effect_type'] ?? json['effectType'],
      effectDuration: json['effect_duration'] ?? json['effectDuration'],
      isAvailable: json['is_available'] ?? json['isAvailable'] ?? true,
      stockLimit: json['stock_limit'] ?? json['stockLimit'],
      stockRemaining: json['stock_remaining'] ?? json['stockRemaining'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'description': description,
      'category': category,
      'price_gems': priceGems,
      'icon_url': iconUrl,
      'effect_type': effectType,
      'effect_duration': effectDuration,
      'is_available': isAvailable,
      'stock_limit': stockLimit,
      'stock_remaining': stockRemaining,
    };
  }

  @override
  List<Object?> get props => [id, name, category, priceGems];
}
