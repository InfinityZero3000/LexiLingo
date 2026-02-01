import '../entities/notification_entity.dart';

/// Notification Repository Interface
/// Defines the contract for notification data operations
abstract class NotificationRepository {
  /// Get all notifications for the current user
  /// Returns a list of notifications sorted by timestamp (newest first)
  Future<List<NotificationEntity>> getNotifications();

  /// Get unread notification count
  Future<int> getUnreadCount();

  /// Get a single notification by ID
  Future<NotificationEntity?> getNotificationById(String id);

  /// Add a new notification (from FCM or local)
  Future<void> addNotification(NotificationEntity notification);

  /// Mark a notification as read
  Future<void> markAsRead(String notificationId);

  /// Mark all notifications as read
  Future<void> markAllAsRead();

  /// Delete a notification
  Future<void> deleteNotification(String notificationId);

  /// Delete all notifications
  Future<void> deleteAllNotifications();

  /// Get notifications grouped by date (Today, Yesterday, Earlier)
  Future<List<NotificationGroup>> getGroupedNotifications();

  /// Stream of notifications for real-time updates
  Stream<List<NotificationEntity>> get notificationsStream;

  /// Stream of unread count for real-time badge updates
  Stream<int> get unreadCountStream;
}
