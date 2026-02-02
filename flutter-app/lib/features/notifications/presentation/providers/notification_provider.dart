import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';

/// Notification Provider
/// Manages notification state and integrates with Firebase Cloud Messaging
class NotificationProvider with ChangeNotifier {
  final NotificationRepository _repository;

  // State
  List<NotificationGroup> _groupedNotifications = [];
  List<NotificationEntity> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  String? _errorMessage;

  // Subscriptions
  StreamSubscription<List<NotificationEntity>>? _notificationsSubscription;
  StreamSubscription<int>? _unreadCountSubscription;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  NotificationProvider({
    required NotificationRepository repository,
  }) : _repository = repository {
    _init();
  }

  // Getters
  List<NotificationGroup> get groupedNotifications => _groupedNotifications;
  List<NotificationEntity> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get hasNotifications => _notifications.isNotEmpty;
  bool get hasUnread => _unreadCount > 0;

  /// Initialize provider and set up listeners
  void _init() {
    // Listen to notification stream
    _notificationsSubscription = _repository.notificationsStream.listen(
      (notifications) {
        _notifications = notifications;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Notifications stream error: $error');
      },
    );

    // Listen to unread count stream
    _unreadCountSubscription = _repository.unreadCountStream.listen(
      (count) {
        _unreadCount = count;
        notifyListeners();
      },
      onError: (error) {
        debugPrint('Unread count stream error: $error');
      },
    );

    // Listen to FCM messages (if not on web)
    if (!kIsWeb) {
      _setupFcmListener();
    }

    // Load initial data
    loadNotifications();
  }

  /// Setup Firebase Cloud Messaging listener
  void _setupFcmListener() {
    try {
      _fcmSubscription = FirebaseMessaging.onMessage.listen(
        (RemoteMessage message) {
          _handleFcmMessage(message);
        },
        onError: (error) {
          debugPrint('FCM stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to setup FCM listener: $e');
    }
  }

  /// Handle incoming FCM message
  Future<void> _handleFcmMessage(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final newNotification = NotificationEntity.fromFcm(
      id: message.messageId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      title: notification.title ?? 'Notification',
      body: notification.body ?? '',
      data: message.data,
    );

    await _repository.addNotification(newNotification);
    await loadNotifications();
  }

  /// Load all notifications
  Future<void> loadNotifications() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _groupedNotifications = await _repository.getGroupedNotifications();
      _notifications = await _repository.getNotifications();
      _unreadCount = await _repository.getUnreadCount();
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load notifications: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Refresh notifications
  Future<void> refreshNotifications() async {
    await loadNotifications();
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _repository.markAsRead(notificationId);
      await loadNotifications();
    } catch (e) {
      _errorMessage = 'Failed to mark notification as read: $e';
      notifyListeners();
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      await _repository.markAllAsRead();
      await loadNotifications();
    } catch (e) {
      _errorMessage = 'Failed to mark all as read: $e';
      notifyListeners();
    }
  }

  /// Delete a notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      await _repository.deleteNotification(notificationId);
      await loadNotifications();
    } catch (e) {
      _errorMessage = 'Failed to delete notification: $e';
      notifyListeners();
    }
  }

  /// Delete all notifications
  Future<void> deleteAllNotifications() async {
    try {
      await _repository.deleteAllNotifications();
      await loadNotifications();
    } catch (e) {
      _errorMessage = 'Failed to delete all notifications: $e';
      notifyListeners();
    }
  }

  /// Add a local notification (for testing or system notifications)
  Future<void> addLocalNotification({
    required String title,
    required String body,
    NotificationType type = NotificationType.general,
    Map<String, dynamic>? data,
  }) async {
    final notification = NotificationEntity(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
    );

    await _repository.addNotification(notification);
    await loadNotifications();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _notificationsSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _fcmSubscription?.cancel();
    super.dispose();
  }
}
