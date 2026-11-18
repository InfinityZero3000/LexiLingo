import 'package:dio/dio.dart' show Options;
import 'package:lexilingo_app/core/network/envelope.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';

class AchievementItem {
  const AchievementItem({
    required this.id,
    required this.name,
    required this.description,
    required this.category,
    required this.rarity,
    required this.conditionType,
    required this.conditionValue,
    required this.xpReward,
    required this.gemsReward,
    required this.isHidden,
    this.badgeIcon = '',
    this.badgeColor = '#4CAF50',
  });

  final String id;
  final String name, description, category, rarity, conditionType;
  final String badgeIcon, badgeColor;
  final int conditionValue, xpReward, gemsReward;
  final bool isHidden;

  factory AchievementItem.fromJson(Map<String, dynamic> json) =>
      AchievementItem(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        description: '${json['description'] ?? ''}',
        category: '${json['category'] ?? ''}',
        rarity: '${json['rarity'] ?? 'common'}',
        conditionType: '${json['condition_type'] ?? ''}',
        conditionValue: (json['condition_value'] as num?)?.toInt() ?? 1,
        xpReward: (json['xp_reward'] as num?)?.toInt() ?? 0,
        gemsReward: (json['gems_reward'] as num?)?.toInt() ?? 0,
        isHidden: json['is_hidden'] == true,
        badgeIcon: '${json['badge_icon'] ?? ''}',
        badgeColor: '${json['badge_color'] ?? '#4CAF50'}',
      );
}

class ShopItem {
  const ShopItem({
    required this.id,
    required this.name,
    required this.description,
    required this.itemType,
    required this.priceGems,
    required this.isAvailable,
    this.stock,
    this.iconUrl = '',
    this.effects = const {},
  });

  final String id;
  final String name, description, itemType, iconUrl;
  final int priceGems;
  final int? stock;
  final bool isAvailable;
  final Map<String, dynamic> effects;

  factory ShopItem.fromJson(Map<String, dynamic> json) => ShopItem(
    id: '${json['id'] ?? ''}',
    name: '${json['name'] ?? ''}',
    description: '${json['description'] ?? ''}',
    itemType: '${json['item_type'] ?? ''}',
    priceGems: (json['price_gems'] as num?)?.toInt() ?? 0,
    isAvailable: json['is_available'] == true,
    stock: (json['stock_quantity'] as num?)?.toInt(),
    iconUrl: '${json['icon_url'] ?? ''}',
    effects: json['effects'] is Map
        ? Map<String, dynamic>.from(json['effects'] as Map)
        : const {},
  );
}

class GamificationRepository {
  ApiClient get _api => ApiClient.instance;

  static List<Map<String, dynamic>> _maps(dynamic body, String fallbackKey) {
    final value = body is Map
        ? body['items'] ?? body[fallbackKey] ?? const []
        : body ?? const [];
    final list = value is List ? value : extractPage(body).items;
    return list
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<List<AchievementItem>> listAchievements() async => _maps(
    await _api.getData(ApiEndpoints.adminAchievements),
    'achievements',
  ).map(AchievementItem.fromJson).toList();

  Future<List<ShopItem>> listShop() async => _maps(
    await _api.getData(
      ApiEndpoints.adminShop,
      params: {'include_unavailable': true},
    ),
    'shop_items',
  ).map(ShopItem.fromJson).toList();

  /// The achievements route reads its fields from the query string.
  Future<void> setHidden(String id, bool hidden) => _api.dio.put(
    '${ApiEndpoints.adminAchievements}/$id',
    queryParameters: {'is_hidden': hidden},
  );

  Future<void> saveAchievement(String? id, Map<String, dynamic> values) =>
      _api.dio.request(
        id == null
            ? ApiEndpoints.adminAchievements
            : '${ApiEndpoints.adminAchievements}/$id',
        options: Options(method: id == null ? 'POST' : 'PUT'),
        queryParameters: values,
      );

  Future<void> setAvailable(String id, bool available) => _api.put(
    '${ApiEndpoints.adminShop}/$id',
    data: {'is_available': available},
  );

  Future<void> saveShop(String? id, Map<String, dynamic> values) => id == null
      ? _api.post(ApiEndpoints.adminShop, data: values)
      : _api.put('${ApiEndpoints.adminShop}/$id', data: values);
}
