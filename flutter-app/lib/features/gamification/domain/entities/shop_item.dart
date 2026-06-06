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
  final Map<String, dynamic> effects;
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
    this.effects = const {},
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
  static const String effectUnlimitedHearts = 'heart_refill';
  static const String effectHintRefill = 'hint_pack';
  static const String effectHeartRefill = 'heart_refill';
  static const String effectAvatar = 'avatar';

  bool get isPowerUp => category == categoryPowerUps;
  bool get isCosmetic => category == categoryCosmetics;
  bool get isBoost => category == categoryBoosts;
  bool get isAvatar => effectType == effectAvatar;
  String? get avatarUrl {
    if (!isAvatar) return null;
    final value = effects['avatar_url'];
    return value is String && value.isNotEmpty ? value : iconUrl;
  }

  bool get isLimitedStock => stockLimit != null && stockLimit! > 0;
  bool get isOutOfStock => isLimitedStock && (stockRemaining ?? 0) <= 0;

  factory ShopItemEntity.fromJson(Map<String, dynamic> json) {
    final itemType =
        json['item_type'] as String? ??
        json['effect_type'] as String? ??
        json['effectType'] as String?;
    final effects = Map<String, dynamic>.from(json['effects'] as Map? ?? {});
    final category = json['category'] as String? ?? _categoryFor(itemType);
    final stockQuantity =
        json['stock_quantity'] as int? ??
        json['stock_remaining'] as int? ??
        json['stockRemaining'] as int?;

    return ShopItemEntity(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      description: json['description'] ?? '',
      category: category,
      priceGems: json['price_gems'] ?? json['priceGems'] ?? 0,
      iconUrl: json['icon_url'] ?? json['iconUrl'] ?? '',
      effectType: itemType,
      effectDuration:
          effects['duration_hours'] as int? ??
          json['effect_duration'] as int? ??
          json['effectDuration'] as int?,
      isAvailable: json['is_available'] ?? json['isAvailable'] ?? true,
      stockLimit:
          json['stock_limit'] as int? ??
          json['stockLimit'] as int? ??
          stockQuantity,
      stockRemaining: stockQuantity,
      effects: effects,
    );
  }

  static String _categoryFor(String? itemType) {
    switch (itemType) {
      case effectDoubleXP:
        return categoryBoosts;
      case effectAvatar:
      case 'theme':
        return categoryCosmetics;
      case effectStreakFreeze:
      case 'hint_pack':
      case effectHeartRefill:
        return categoryPowerUps;
      default:
        return categorySpecial;
    }
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
      'effects': effects,
    };
  }

  @override
  List<Object?> get props => [id, name, category, priceGems, effects];
}
