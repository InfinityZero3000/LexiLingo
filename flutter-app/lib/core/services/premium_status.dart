import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';

/// The backend answers first; the RevenueCat SDK cache is consulted only when
/// the backend cannot be reached, so a paying learner is not locked out offline.
Future<bool> resolvePremium({Future<bool> Function()? isPremiumFromSdk}) async {
  final sdk = isPremiumFromSdk ?? () => PurchasesService.instance.isPremium;
  if (!sl.isRegistered<EntitlementService>()) return sdk();
  final active = await sl<EntitlementService>().fetchActive();
  return active ?? await sdk();
}
