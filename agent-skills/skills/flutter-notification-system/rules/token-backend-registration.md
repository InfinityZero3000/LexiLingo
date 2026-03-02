---
name: token-backend-registration
description: After login and after Firebase is initialized, register the FCM token with the backend via POST /api/devices/token. Refresh on onTokenRefresh. Unregister (DELETE) on logout. Store token in SharedPreferences to avoid duplicate registration.
impact: HIGH
---

# FCM Token Registration with Backend

## Context

`FirebaseMessagingService` already retrieves `_fcmToken` and has a `TODO: Send new token to backend` comment. Without registering the token, the backend cannot send push notifications to this device.

## Backend API

```
POST   /api/devices/token     → register / update token
DELETE /api/devices/token     → unregister on logout
```

## Correct Implementation

### 1. Token Registration Service

```dart
// lib/features/user/data/datasources/device_token_datasource.dart
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/network/api_client.dart';

class DeviceTokenDataSource {
  static const String _registeredTokenKey = 'registered_fcm_token';
  final ApiClient _apiClient;

  DeviceTokenDataSource(this._apiClient);

  /// Register or update FCM token with backend.
  /// Skips if the same token is already registered (avoids redundant calls).
  Future<void> registerToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    final existingToken = prefs.getString(_registeredTokenKey);

    if (existingToken == token) return; // Already registered

    try {
      await _apiClient.post('/api/devices/token', data: {
        'token': token,
        'platform': _detectPlatform(),
      });
      await prefs.setString(_registeredTokenKey, token);
    } catch (e) {
      // Non-fatal — user can still use app, just won't receive push notifications
      debugPrint('⚠️ FCM token registration failed: $e');
    }
  }

  /// Remove token from backend on logout.
  Future<void> unregisterToken() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_registeredTokenKey);
    if (token == null) return;

    try {
      await _apiClient.delete('/api/devices/token', data: {'token': token});
      await prefs.remove(_registeredTokenKey);
    } catch (e) {
      debugPrint('⚠️ FCM token unregistration failed: $e');
    }
  }

  String _detectPlatform() {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'unknown';
  }
}
```

### 2. Call Registration After Login

```dart
// In AuthProvider or UserProvider, after successful login:
Future<void> _postLoginSetup() async {
  // Register FCM token
  final fcmToken = FirebaseMessagingService.instance.token;
  if (fcmToken != null) {
    await _deviceTokenDataSource.registerToken(fcmToken);
  }

  // Also listen for token refreshes during this session
  FirebaseMessagingService.instance.onTokenRefresh.listen((newToken) {
    _deviceTokenDataSource.registerToken(newToken);
  });
}
```

### 3. FirebaseMessagingService — Fill the TODO

```dart
// lib/core/services/firebase_messaging_service.dart
// Replace the TODO comment:

// Listen for token refresh
_messaging.onTokenRefresh.listen((newToken) {
  _fcmToken = newToken;
  debugPrint('📱 FCM Token refreshed: $newToken');
  // Emit to a stream so providers can react
  _tokenRefreshController.add(newToken);
});

// Add to class:
final StreamController<String> _tokenRefreshController =
    StreamController<String>.broadcast();
Stream<String> get onTokenRefresh => _tokenRefreshController.stream;
```

### 4. Unregister on Logout

```dart
// In AuthProvider.signOut():
await _deviceTokenDataSource.unregisterToken();
await FirebaseAuth.instance.signOut();
```

## Incorrect Implementation

```dart
// Anti-pattern: registering every app launch (causes backend duplicates)
void initState() {
  super.initState();
  FirebaseMessaging.instance.getToken().then((token) {
    _apiClient.post('/api/devices/token', data: {'token': token}); // ❌ no dedup check
  });
}

// Anti-pattern: not unregistering on logout (device receives notifications after logout)
await FirebaseAuth.instance.signOut(); // ❌ FCM token still active on backend
```
