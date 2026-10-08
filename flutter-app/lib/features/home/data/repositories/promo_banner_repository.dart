import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/home/data/models/promo_banner.dart';

class PromoBannerRepository {
  PromoBannerRepository(this._apiClient);

  final ApiClient _apiClient;

  Future<List<PromoBanner>> getActiveBanners({String position = 'hero'}) async {
    final r = await _apiClient.get('/banners/active?position=$position');
    final success = r['success'];
    if (success is bool && !success) return const [];
    final data = r.containsKey('data') ? r['data'] : r;
    if (data is! List) return const [];
    return data
        .map((e) => PromoBanner.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
