import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/home/data/models/promo_banner.dart';
import 'package:lexilingo_app/features/home/data/repositories/promo_banner_repository.dart';

/// Loads the home hero promo banner and tracks which ones this device has
/// dismissed. Failures degrade silently — a broken banner feed must never
/// block or error out the home screen.
class PromoBannerProvider with ChangeNotifier {
  PromoBannerProvider(this._repository);

  static const _dismissedKey = 'dismissed_promo_banner_ids';

  final PromoBannerRepository _repository;
  List<PromoBanner> _banners = [];
  Set<String> _dismissedIds = {};
  bool _isLoading = false;

  bool get isLoading => _isLoading;

  PromoBanner? get visibleBanner {
    for (final banner in _banners) {
      if (!_dismissedIds.contains(banner.id)) return banner;
    }
    return null;
  }

  Future<void> load() async {
    _isLoading = true;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      _dismissedIds = (prefs.getStringList(_dismissedKey) ?? []).toSet();
      _banners = await _repository.getActiveBanners();
    } catch (_) {
      _banners = [];
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> dismiss(String bannerId) async {
    _dismissedIds = {..._dismissedIds, bannerId};
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_dismissedKey, _dismissedIds.toList());
    } catch (_) {
      // Dismissal still holds for this session even if persistence fails.
    }
  }
}
