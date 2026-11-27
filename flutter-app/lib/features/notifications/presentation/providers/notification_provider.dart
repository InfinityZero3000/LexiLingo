import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/state/reset_epoch.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:flutter/foundation.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/repositories/notification_repository.dart';
import '../../domain/services/review_reminder_notification_sync_service.dart';

/// Notification Provider
/// Manages notification state and integrates with Firebase Cloud Messaging
class NotificationProvider with ChangeNotifier, ResetEpoch {
  final NotificationRepository _repository;

  // State
  List<NotificationGroup> _groupedNotifications = [];
  List<NotificationEntity> _notifications = [];
  int _unreadCount = 0;
  bool _isLoading = false;
  UiText? _errorMessage;

  // Undo-delete buffer: stores the last deleted notification temporarily
  NotificationEntity? _pendingDeletedNotification;

  // Subscriptions
  StreamSubscription<List<NotificationEntity>>? _notificationsSubscription;
  StreamSubscription<int>? _unreadCountSubscription;
  StreamSubscription<RemoteMessage>? _fcmSubscription;

  final ReviewReminderNotificationSyncService? _reviewReminderSyncService;
  final bool _listenToForegroundFcm;

  NotificationProvider({
    required NotificationRepository repository,
    ReviewReminderNotificationSyncService? reviewReminderSyncService,
    bool? listenToForegroundFcm,
  }) : _repository = repository,
       _reviewReminderSyncService = reviewReminderSyncService,
       _listenToForegroundFcm = listenToForegroundFcm ?? !kIsWeb {
    _init();
    LocaleService.languageSwitches.addListener(_onLanguageSwitched);
  }

  /// Group headings and the review reminder row are stored translated.
  void _onLanguageSwitched() =>
      unawaited(loadNotifications(syncReviewReminder: true));

  // Getters
  List<NotificationGroup> get groupedNotifications => _groupedNotifications;
  List<NotificationEntity> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage?.resolve();
  bool get hasNotifications => _notifications.isNotEmpty;
  bool get hasUnread => _unreadCount > 0;
  NotificationEntity? get pendingDeletedNotification =>
      _pendingDeletedNotification;

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
    if (_listenToForegroundFcm) {
      _setupFcmListener();
    }

    // Load initial data
    unawaited(loadNotifications(syncReviewReminder: true));
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
  Future<void> loadNotifications({bool syncReviewReminder = false}) async {
    final epoch = resetEpoch;
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      if (syncReviewReminder) {
        await _syncReviewReminderNotification();
      }
      final grouped = await _repository.getGroupedNotifications();
      final all = await _repository.getNotifications();
      final unread = await _repository.getUnreadCount();
      if (isStale(epoch)) return;
      _groupedNotifications = grouped;
      _notifications = all;
      _unreadCount = unread;
      _errorMessage = null;
    } catch (e) {
      if (isStale(epoch)) return;
      _errorMessage = UiText.key('notifications.failedToLoad');
      debugPrint('Failed to load notifications: $e');
    } finally {
      if (!isStale(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  /// Refresh notifications
  Future<void> refreshNotifications() async {
    await loadNotifications(syncReviewReminder: true);
  }

  Future<void> _syncReviewReminderNotification() async {
    final syncService = _reviewReminderSyncService;
    if (syncService == null) return;

    try {
      await syncService.sync();
    } catch (e) {
      debugPrint('Review reminder notification sync failed: $e');
    }
  }

  static const emailVerificationId = 'email_verification_pending';

  /// Keeps one "verify your email" entry in the inbox while the account is
  /// unverified, and removes it once it is. It replaced a banner pinned to the
  /// top of Home: a standing request belongs with the other requests.
  Future<void> syncEmailVerification({
    required String? email,
    required bool verified,
  }) async {
    final epoch = resetEpoch;
    final existing = await _repository.getNotificationById(emailVerificationId);
    if (isStale(epoch)) return;
    if (verified || email == null || email.isEmpty) {
      if (existing == null) return;
      await _repository.deleteNotification(emailVerificationId);
    } else {
      // Rewritten each time so it follows the UI language; read state and
      // date are kept, or every launch would mark it new again.
      await _repository.addNotification(
        NotificationEntity(
          id: emailVerificationId,
          type: NotificationType.system,
          title: 'notifications.verifyEmailTitle'.tr(),
          body: 'notifications.verifyEmailBody'.tr(namedArgs: {'email': email}),
          timestamp: existing?.timestamp ?? DateTime.now(),
          isRead: existing?.isRead ?? false,
          data: const {
            'route': '/profile/edit',
            'source': 'email_verification',
          },
          iconIdentifier: 'mark_email_unread',
          colorHex: '#9C27B0',
        ),
      );
    }
    if (!isStale(epoch)) await loadNotifications();
  }

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId) async {
    try {
      await _repository.markAsRead(notificationId);
      await loadNotifications();
    } catch (e) {
      _errorMessage = UiText.key('notifications.markReadFailed');
      debugPrint('Failed to mark notification as read: $e');
      notifyListeners();
    }
  }

  /// Mark all notifications as read
  Future<void> markAllAsRead() async {
    try {
      await _repository.markAllAsRead();
      await loadNotifications();
    } catch (e) {
      _errorMessage = UiText.key('notifications.markReadFailed');
      debugPrint('Failed to mark all as read: $e');
      notifyListeners();
    }
  }

  /// Delete a notification with optional undo buffer.
  /// Pass [forUndo] = true (default) to buffer for undo-SnackBar.
  Future<void> deleteNotification(
    String notificationId, {
    bool forUndo = true,
  }) async {
    if (forUndo) {
      // Snapshot the entity BEFORE deletion so undo can restore it.
      // Use firstWhereOrNull-style guard to avoid throwing on missing id.
      final match = _notifications.where((n) => n.id == notificationId);
      _pendingDeletedNotification = match.isNotEmpty ? match.first : null;
    }
    try {
      await _repository.deleteNotification(notificationId);
      await loadNotifications();
    } catch (e) {
      _errorMessage = UiText.key('notifications.deleteFailed');
      debugPrint('Failed to delete notification: $e');
      _pendingDeletedNotification = null;
      notifyListeners();
    }
  }

  /// Restore the last deleted notification (undo swipe-to-delete).
  Future<void> undoDelete() async {
    final n = _pendingDeletedNotification;
    if (n == null) return;
    _pendingDeletedNotification = null;
    try {
      await _repository.addNotification(n);
      await loadNotifications();
    } catch (e) {
      _errorMessage = UiText.key('notifications.restoreFailed');
      debugPrint('Failed to restore notification: $e');
      notifyListeners();
    }
  }

  /// Clear the undo buffer (called when SnackBar times out without Undo).
  void commitDelete() {
    _pendingDeletedNotification = null;
  }

  /// Delete all notifications
  Future<void> deleteAllNotifications() async {
    try {
      await _repository.deleteAllNotifications();
      await loadNotifications();
    } catch (e) {
      _errorMessage = UiText.key('notifications.deleteFailed');
      debugPrint('Failed to delete all notifications: $e');
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

  /// Notifications are stored per user; this empties the screen and the next
  /// sign-in reloads from that user's own store.
  void reset() {
    bumpResetEpoch();
    _groupedNotifications = [];
    _notifications = [];
    _unreadCount = 0;
    _isLoading = false;
    _errorMessage = null;
    _pendingDeletedNotification = null;
    notifyListeners();
  }

  /// Clear error message
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  bool _disposed = false;

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    LocaleService.languageSwitches.removeListener(_onLanguageSwitched);
    _notificationsSubscription?.cancel();
    _unreadCountSubscription?.cancel();
    _fcmSubscription?.cancel();
    super.dispose();
  }
}
