import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/network/api_client.dart';

/// Syncs server-verified entitlement state (backend calls RevenueCat
/// directly — this never sends purchase data, only asks the backend to
/// re-check). Call after purchase/restore and once per authenticated
/// session start.
class EntitlementService {
  final ApiClient apiClient;

  EntitlementService({required this.apiClient});

  Future<bool> sync({String entitlementId = 'premium'}) async {
    try {
      final data = await apiClient.post(
        '/entitlements/sync?entitlement_id=$entitlementId',
      );
      return data['active'] == true;
    } catch (e) {
      debugPrint('EntitlementService.sync error: $e');
      return false;
    }
  }

  Future<bool> fetchCached({String entitlementId = 'premium'}) async {
    try {
      final data = await apiClient.get('/entitlements/me?entitlement_id=$entitlementId');
      return data['active'] == true;
    } catch (e) {
      debugPrint('EntitlementService.fetchCached error: $e');
      return false;
    }
  }
}
