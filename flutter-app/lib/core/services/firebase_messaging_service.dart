import 'dart:async';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_client.dart';

/// Firebase Cloud Messaging Service
/// Handles push notifications from Firebase
class FirebaseMessagingService {
  static FirebaseMessagingService? _instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  String? _fcmToken;
  ApiClient? _apiClient;
  static const String _kRegisteredTokenKey = 'registered_fcm_token';
  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();

  FirebaseMessagingService._();

  static FirebaseMessagingService get instance {
    _instance ??= FirebaseMessagingService._();
    return _instance!;
  }

  /// Stream of incoming messages when app is in foreground
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  /// Get current FCM token
  String? get token => _fcmToken;

  /// Initialize Firebase Messaging
  Future<void> initialize() async {
    try {
      // Request permission (required for iOS and web)
      await _requestPermission();

      // Get FCM token
      _fcmToken = await _messaging.getToken();
      debugPrint('📱 FCM Token: $_fcmToken');

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        debugPrint('📱 FCM Token refreshed: $newToken');
        // Re-register the updated token with the backend (fire-and-forget).
        if (_apiClient != null) {
          registerTokenWithBackend(_apiClient!, forceUpdate: true);
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          '📩 Foreground message received: ${message.notification?.title}',
        );
        _messageController.add(message);
        _handleMessage(message);
      });

      // Handle background/terminated message tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📩 Message opened app: ${message.notification?.title}');
        _handleMessageTap(message);
      });

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('📩 Initial message: ${initialMessage.notification?.title}');
        _handleMessageTap(initialMessage);
      }

      debugPrint('✅ FirebaseMessagingService initialized');
    } catch (e) {
      debugPrint('❌ FirebaseMessagingService initialization failed: $e');
    }
  }

  /// Request notification permissions
  Future<NotificationSettings> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      announcement: false,
      badge: true,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
      sound: true,
    );

    debugPrint('📱 Notification permission: ${settings.authorizationStatus}');
    return settings;
  }

  /// Handle incoming message (show local notification)
  void _handleMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    // For foreground messages, you may want to show a local notification
    // This is handled by the NotificationService
    debugPrint('📩 Message: ${notification.title} - ${notification.body}');
  }

  // ──────────────────────────────────────────────────────────────────────────
  //  Device Token Registration
  // ──────────────────────────────────────────────────────────────────────────

  /// Register the current FCM token with the LexiLingo backend.
  ///
  /// - Deduplicates: skips the API call if the token has already been sent
  ///   (unless [forceUpdate] is true, e.g. on token refresh).
  /// - Safe to call multiple times; the backend performs an upsert.
  /// - Should be called after a successful sign-in.
  Future<void> registerTokenWithBackend(
    ApiClient client, {
    bool forceUpdate = false,
  }) async {
    if (kIsWeb) return;
    final token = _fcmToken;
    if (token == null || token.isEmpty) return;

    _apiClient = client;

    // Dedup: skip if token was already registered and force-update is off.
    if (!forceUpdate) {
      final prefs = await SharedPreferences.getInstance();
      final last = prefs.getString(_kRegisteredTokenKey);
      if (last == token) {
        debugPrint('📱 FCM token already registered – skipping.');
        return;
      }
    }

    try {
      final deviceId = await _getDeviceId();
      final deviceType = _getDeviceType();

      await client.post(
        '/api/devices',
        body: {
          'device_id': deviceId,
          'device_type': deviceType,
          'fcm_token': token,
        },
      );

      // Persist the successfully registered token to skip future duplicates.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRegisteredTokenKey, token);
      debugPrint('✅ FCM token registered with backend ($deviceType)');
    } catch (e) {
      debugPrint('⚠️ FCM token registration failed: $e');
    }
  }

  /// Clear the stored registered token so it will be re-registered on next
  /// call to [registerTokenWithBackend]. Call on sign-out.
  Future<void> clearRegisteredToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRegisteredTokenKey);
    debugPrint('📱 FCM registered-token cache cleared.');
  }

  /// Returns a stable unique identifier for this device.
  /// Uses device hardware info if available, otherwise falls back to a
  /// UUID stored in SharedPreferences.
  Future<String> _getDeviceId() async {
    try {
      final info = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final android = await info.androidInfo;
        return android.id;
      } else if (Platform.isIOS) {
        final ios = await info.iosInfo;
        return ios.identifierForVendor ?? _generateOrFetchUuid();
      }
    } catch (_) {}
    return _generateOrFetchUuid();
  }

  Future<String> _generateOrFetchUuid() async {
    const key = 'lexilingo_device_uuid';
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString(key);
    if (id == null) {
      // Use timestamp-based ID as a lightweight UUID substitute.
      id = 'flutter-${DateTime.now().millisecondsSinceEpoch}';
      await prefs.setString(key, id);
    }
    return id;
  }

  String _getDeviceType() {
    if (kIsWeb) return 'web';
    try {
      if (Platform.isAndroid) return 'android';
      if (Platform.isIOS) return 'ios';
    } catch (_) {}
    return 'unknown';
  }

  /// Handle message tap (navigate to relevant screen)
  void _handleMessageTap(RemoteMessage message) {
    final data = message.data;
    debugPrint('Message data: $data');

    // Parse data and navigate accordingly
    final type = data['type'] as String?;
    // ignore: unused_local_variable
    final targetId = data['target_id'] as String?;

    switch (type) {
      case 'streak_reminder':
        // Navigate to home/streak screen
        debugPrint('Navigate to streak screen');
        break;
      case 'lesson_reminder':
        // Navigate to learning screen
        debugPrint('Navigate to learning screen');
        break;
      case 'achievement':
        // Navigate to achievements screen
        debugPrint('Navigate to achievements screen');
        break;
      case 'new_content':
        // Navigate to courses screen
        debugPrint('Navigate to courses screen');
        break;
      default:
        // Navigate to home
        debugPrint('Navigate to home screen');
    }
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      debugPrint('Topic subscription not supported on web');
      return;
    }
    await _messaging.subscribeToTopic(topic);
    debugPrint('📱 Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      debugPrint('Topic unsubscription not supported on web');
      return;
    }
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint('📱 Unsubscribed from topic: $topic');
  }

  /// Get APNS token (iOS only)
  Future<String?> getAPNSToken() async {
    if (kIsWeb) return null;
    return await _messaging.getAPNSToken();
  }

  /// Dispose resources
  void dispose() {
    _messageController.close();
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint('📩 Background message: ${message.notification?.title}');
  // Handle background message here
}
