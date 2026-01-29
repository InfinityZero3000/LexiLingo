import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../models/auth_models.dart';

/// Service to manage device information and registration
/// Handles device tracking for backend Phase 1 user_devices table
class DeviceManager {
  final DeviceInfoPlugin _deviceInfo = DeviceInfoPlugin();

  DeviceManager();

  /// Get current device information
  Future<DeviceInfo> getDeviceInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    String deviceId;
    String deviceType;
    String? deviceName;
    String? osVersion;

    if (kIsWeb) {
      // Web platform
      try {
        final webInfo = await _deviceInfo.webBrowserInfo;
        deviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
        deviceType = 'web';
        deviceName = webInfo.browserName.name;
        osVersion = webInfo.platform ?? 'Web';
      } catch (e) {
        deviceId = 'web-${DateTime.now().millisecondsSinceEpoch}';
        deviceType = 'web';
        deviceName = 'Web Browser';
        osVersion = 'Web';
      }
    } else {
      // Native platforms
      try {
        final baseInfo = await _deviceInfo.deviceInfo;
        deviceId = baseInfo.data['id']?.toString() ?? 
                   baseInfo.data['identifierForVendor']?.toString() ??
                   'device-${DateTime.now().millisecondsSinceEpoch}';
        
        if (baseInfo.data.containsKey('brand')) {
          // Android
          deviceType = 'android';
          deviceName = '${baseInfo.data['brand']} ${baseInfo.data['model']}';
          osVersion = 'Android ${baseInfo.data['version']?['release'] ?? 'Unknown'}';
        } else if (baseInfo.data.containsKey('systemName')) {
          // iOS
          deviceType = 'ios';
          deviceName = '${baseInfo.data['name']} ${baseInfo.data['model']}';
          osVersion = '${baseInfo.data['systemName']} ${baseInfo.data['systemVersion']}';
        } else {
          deviceType = 'unknown';
          deviceName = 'Unknown Device';
          osVersion = 'Unknown';
        }
      } catch (e) {
        deviceId = 'device-${DateTime.now().millisecondsSinceEpoch}';
        deviceType = 'unknown';
        deviceName = 'Unknown Device';
        osVersion = 'Unknown';
      }
    }

    return DeviceInfo(
      deviceId: deviceId,
      deviceType: deviceType,
      deviceName: deviceName,
      fcmToken: null, // FCM handled separately
      appVersion: packageInfo.version,
      osVersion: osVersion,
    );
  }

  /// Request notification permissions
  Future<bool> requestNotificationPermissions() async {
    // Not critical for web
    return true;
  }

  /// Refresh FCM token if needed
  Future<String?> refreshFCMToken() async {
    return null;
  }

  /// Listen to FCM token refreshes
  Stream<String> get onTokenRefresh => const Stream.empty();
}
