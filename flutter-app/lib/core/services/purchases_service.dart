import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

/// RevenueCat wrapper for subscription management.
///
/// Set REVENUECAT_API_KEY_IOS and REVENUECAT_API_KEY_ANDROID in your
/// environment / .env before enabling premium features in production.
class PurchasesService {
  static final PurchasesService instance = PurchasesService._();
  PurchasesService._();

  static const String _entitlementId = 'premium';

  bool _isConfigured = false;

  Future<void> init({
    required String? iosApiKey,
    required String? androidApiKey,
  }) async {
    if (kIsWeb) return;
    final key = defaultTargetPlatform == TargetPlatform.iOS ? iosApiKey : androidApiKey;
    if (key == null || key.isEmpty) {
      debugPrint('PurchasesService: no API key for ${defaultTargetPlatform.name}; skipping init');
      return;
    }
    try {
      await Purchases.setLogLevel(kDebugMode ? LogLevel.debug : LogLevel.warn);
      await Purchases.configure(PurchasesConfiguration(key));
      _isConfigured = true;
      debugPrint('RevenueCat configured');
    } catch (e) {
      debugPrint('PurchasesService init error: $e');
    }
  }

  Future<bool> get isPremium async {
    if (!_isConfigured) return false;
    try {
      final info = await Purchases.getCustomerInfo();
      return info.entitlements.active.containsKey(_entitlementId);
    } catch (e) {
      debugPrint('isPremium check error: $e');
      return false;
    }
  }

  Future<List<Package>> getOfferings() async {
    if (!_isConfigured) return [];
    try {
      final offerings = await Purchases.getOfferings();
      return offerings.current?.availablePackages ?? [];
    } catch (e) {
      debugPrint('getOfferings error: $e');
      return [];
    }
  }

  /// Returns true on success, false on user cancellation.
  /// Throws [PlatformException] for payment/network errors so the caller can
  /// surface a meaningful error message.
  Future<bool> purchase(Package package) async {
    if (!_isConfigured) return false;
    try {
      final info = await Purchases.purchasePackage(package);
      return info.entitlements.active.containsKey(_entitlementId);
    } on PlatformException catch (e) {
      final errorCode = PurchasesErrorHelper.getErrorCode(e);
      if (errorCode == PurchasesErrorCode.purchaseCancelledError) return false;
      rethrow;
    }
  }

  Future<bool> restore() async {
    if (!_isConfigured) return false;
    try {
      final info = await Purchases.restorePurchases();
      return info.entitlements.active.containsKey(_entitlementId);
    } catch (e) {
      debugPrint('Restore error: $e');
      return false;
    }
  }

  Future<void> identifyUser(String userId) async {
    if (!_isConfigured) return;
    try {
      await Purchases.logIn(userId);
    } catch (e) {
      debugPrint('RevenueCat identify error: $e');
    }
  }

  Future<void> logout() async {
    if (!_isConfigured) return;
    try {
      await Purchases.logOut();
    } catch (e) {
      debugPrint('RevenueCat logout error: $e');
    }
  }
}
