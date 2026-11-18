import '../../../core/constants/api_endpoints.dart';
import 'package:lexilingo_app/core/network/envelope.dart';
import '../../../core/network/api_client.dart';

class BannerItem {
  final String id, title, imageUrl, position;
  final String? description,
      linkUrl,
      targetMinLevel,
      targetMaxLevel,
      targetLanguage;
  final int priority;
  final bool isActive;
  final DateTime? startAt, endAt;

  const BannerItem({
    required this.id,
    required this.title,
    required this.imageUrl,
    required this.position,
    this.description,
    this.linkUrl,
    this.targetMinLevel,
    this.targetMaxLevel,
    this.targetLanguage,
    required this.priority,
    required this.isActive,
    this.startAt,
    this.endAt,
  });

  factory BannerItem.fromJson(Map<String, dynamic> json) => BannerItem(
    id: json['id']?.toString() ?? '',
    title: json['title'] ?? '',
    imageUrl: json['image_url'] ?? '',
    position: json['position'] ?? 'hero',
    description: json['description']?.toString(),
    linkUrl: json['link_url']?.toString(),
    targetMinLevel: json['target_min_level']?.toString(),
    targetMaxLevel: json['target_max_level']?.toString(),
    targetLanguage: json['target_language']?.toString(),
    priority: (json['priority'] as num?)?.toInt() ?? 0,
    isActive: json['is_active'] != false,
    startAt: json['start_at'] != null
        ? DateTime.tryParse(json['start_at'])
        : null,
    endAt: json['end_at'] != null ? DateTime.tryParse(json['end_at']) : null,
  );
}

class BannerRepository {
  ApiClient get _api => ApiClient.instance;

  Future<List<BannerItem>> listBanners() async {
    final body = await _api.getData(
      ApiEndpoints.adminBanners,
      params: {'limit': 200},
    );
    return extractPage(body).items
        .whereType<Map>()
        .map((e) => BannerItem.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }

  Future<void> createBanner(Map<String, dynamic> data) =>
      _api.post(ApiEndpoints.adminBanners, data: data);
  Future<void> updateBanner(String id, Map<String, dynamic> data) =>
      _api.put('${ApiEndpoints.adminBanners}/$id', data: data);
  Future<void> setActive(String id, bool active) =>
      updateBanner(id, {'is_active': active});
}
