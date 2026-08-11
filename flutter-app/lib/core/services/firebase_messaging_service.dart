import 'dart:async';
import 'dart:io' show Platform;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:lexilingo_app/features/notifications/domain/services/notification_navigation_service.dart';

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

      // Check if running on iOS simulator avoiding APNS hang
      bool isSimulator = false;
      if (!kIsWeb && Platform.isIOS) {
        try {
          final iosInfo = await DeviceInfoPlugin().iosInfo;
          isSimulator = !iosInfo.isPhysicalDevice;
        } catch (_) {}
      }

      // Get FCM token
      try {
        if (isSimulator) {
          debugPrint(
            ' Running on iOS Simulator: Skipping real FCM token request to avoid APNS errors.',
          );
          _fcmToken = 'simulator_dummy_token';
        } else {
          _fcmToken = await _messaging.getToken().timeout(
            const Duration(seconds: 5),
          );
          if (kDebugMode) {
            debugPrint('FCM Token: ${_maskToken(_fcmToken)}');
          }
        }
      } catch (e) {
        debugPrint(
          'Could not get FCM token (expected if APNS/FCM not fully setup): $e',
        );
      }

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        if (kDebugMode) {
          debugPrint(' FCM Token refreshed: ${_maskToken(newToken)}');
        }
        // Re-register the updated token with the backend (fire-and-forget).
        if (_apiClient != null) {
          registerTokenWithBackend(_apiClient!, forceUpdate: true);
        }
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint(
          ' Foreground message received: ${message.notification?.title}',
        );
        _messageController.add(message);
        _handleMessage(message);
      });

      // Handle background/terminated message tap
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint(' Message opened app: ${message.notification?.title}');
        _handleMessageTap(message);
      });

      // Check if app was opened from a notification
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint(' Initial message: ${initialMessage.notification?.title}');
        _handleMessageTap(initialMessage);
      }

      debugPrint(' FirebaseMessagingService initialized');
    } catch (e) {
      debugPrint(' FirebaseMessagingService initialization failed: $e');
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

    debugPrint(' Notification permission: ${settings.authorizationStatus}');
    return settings;
  }

  /// Handle incoming message (show local notification)
  void _handleMessage(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    // For foreground messages, you may want to show a local notification
    // This is handled by the NotificationService
    debugPrint(' Message: ${notification.title} - ${notification.body}');
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
        debugPrint('FCM token already registered – skipping.');
        return;
      }
    }

    try {
      final deviceId = await _getDeviceId();
      final deviceType = _getDeviceType();

      await client.post(
        '/devices',
        body: {
          'device_id': deviceId,
          'device_type': deviceType,
          'fcm_token': token,
        },
      );

      // Persist the successfully registered token to skip future duplicates.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kRegisteredTokenKey, token);
      debugPrint('FCM token registered with backend ($deviceType)');
    } catch (e) {
      debugPrint('FCM token registration failed: $e');
    }
  }

  /// Clear the stored registered token so it will be re-registered on next
  /// call to [registerTokenWithBackend]. Call on sign-out.
  Future<void> clearRegisteredToken() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kRegisteredTokenKey);
    debugPrint(' FCM registered-token cache cleared.');
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

    final notification = NotificationEntity.fromFcm(
      id: message.messageId ?? 'fcm_${DateTime.now().microsecondsSinceEpoch}',
      title:
          message.notification?.title ??
          _readDataString(data, 'title') ??
          'Notification',
      body: message.notification?.body ?? _readDataString(data, 'body') ?? '',
      data: Map<String, dynamic>.from(data),
    );

    NotificationNavigationService.open(notification);
    debugPrint(
      'Navigate notification to ${notification.destinationRoute ?? 'root'}',
    );
  }

  String? _readDataString(Map<String, dynamic> data, String key) {
    final value = data[key];
    if (value is! String) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  /// Subscribe to a topic
  Future<void> subscribeToTopic(String topic) async {
    if (kIsWeb) {
      debugPrint('Topic subscription not supported on web');
      return;
    }
    await _messaging.subscribeToTopic(topic);
    debugPrint(' Subscribed to topic: $topic');
  }

  /// Unsubscribe from a topic
  Future<void> unsubscribeFromTopic(String topic) async {
    if (kIsWeb) {
      debugPrint('Topic unsubscription not supported on web');
      return;
    }
    await _messaging.unsubscribeFromTopic(topic);
    debugPrint(' Unsubscribed from topic: $topic');
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

  String _maskToken(String? token) {
    if (token == null || token.isEmpty) return '<empty>';
    if (token.length <= 10) return '***';
    final head = token.substring(0, 6);
    final tail = token.substring(token.length - 4);
    return '$head...$tail';
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(' Background message: ${message.notification?.title}');
  // Handle background message here
}
