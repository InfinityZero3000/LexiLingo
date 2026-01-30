import 'dart:async';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;

/// Firebase Cloud Messaging Service
/// Handles push notifications from Firebase
class FirebaseMessagingService {
  static FirebaseMessagingService? _instance;
  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  String? _fcmToken;
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
        // TODO: Send new token to backend
      });
      
      // Handle foreground messages
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📩 Foreground message received: ${message.notification?.title}');
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
