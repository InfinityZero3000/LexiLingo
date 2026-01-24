import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/auth_models.dart';

/// Service to manage device information and registration
/// Handles device tracking for backend Phase 1 user_devices table
class DeviceManager {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  /// Get current device information
  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    String deviceId;
    String deviceType;
    String? deviceName;
    String? osVersion;

    if (Platform.isAndroid) {
      final androidInfo = await _deviceInfo.androidInfo;
      deviceId = androidInfo.id;  // Android ID
      deviceType = 'android';
      deviceName = '${androidInfo.brand} ${androidInfo.model}';
      osVersion = 'Android ${androidInfo.version.release}';
    } else if (Platform.isIOS) {
      final iosInfo = await _deviceInfo.iosInfo;
      deviceId = iosInfo.identifierForVendor ?? 'unknown';
      deviceType = 'ios';
      deviceName = '${iosInfo.name} ${iosInfo.model}';
      osVersion = 'iOS ${iosInfo.systemVersion}';
    } else {
      deviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
      deviceType = 'web';
      deviceName = 'Web Browser';
      osVersion = 'Web';
    }

    // Get FCM token for push notifications
    String? fcmToken;
    try {
      fcmToken = await _messaging.getToken();
    } catch (e) {
      // FCM not configured or permission denied
      fcmToken = null;
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      fcmToken: fcmToken,
      appVersion: packageInfo.version,
      osVersion: osVersion,
    );
  }

  /// Request notification permissions (iOS specific)
  Future<bool> requestNotificationPermissions() async {
    if (!Platform.isIOS) return true;

    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    return settings.authorizationStatus == AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Refresh FCM token if needed
  Future<String?> refreshFCMToken() async {
    try {
      return await _messaging.getToken();
    } catch (e) {
      return null;
    }
  }

  /// Listen to FCM token refreshes
  Stream<String> get onTokenRefresh => _messaging.onTokenRefresh;
}
