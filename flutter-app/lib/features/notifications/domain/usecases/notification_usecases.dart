import '../entities/notification_entity.dart';
import '../repositories/notification_repository.dart';

/// Get all notifications use case
class GetNotificationsUseCase {
  final NotificationRepository repository;

  GetNotificationsUseCase(this.repository);

  Future<List<NotificationEntity>> call() {
    return repository.getNotifications();
  }
}

/// Get grouped notifications use case
class GetGroupedNotificationsUseCase {
  final NotificationRepository repository;

  GetGroupedNotificationsUseCase(this.repository);

  Future<List<NotificationGroup>> call() {
    return repository.getGroupedNotifications();
  }
}

/// Get unread count use case
class GetUnreadCountUseCase {
  final NotificationRepository repository;

  GetUnreadCountUseCase(this.repository);

  Future<int> call() {
    return repository.getUnreadCount();
  }
}

/// Mark notification as read use case
class MarkNotificationAsReadUseCase {
  final NotificationRepository repository;

  MarkNotificationAsReadUseCase(this.repository);

  Future<void> call(String notificationId) {
    return repository.markAsRead(notificationId);
  }
}

/// Mark all notifications as read use case
class MarkAllNotificationsAsReadUseCase {
  final NotificationRepository repository;

  MarkAllNotificationsAsReadUseCase(this.repository);

  Future<void> call() {
    return repository.markAllAsRead();
  }
}

/// Delete notification use case
class DeleteNotificationUseCase {
  final NotificationRepository repository;

  DeleteNotificationUseCase(this.repository);

  Future<void> call(String notificationId) {
    return repository.deleteNotification(notificationId);
  }
}

/// Add notification use case
class AddNotificationUseCase {
  final NotificationRepository repository;

  AddNotificationUseCase(this.repository);

  Future<void> call(NotificationEntity notification) {
    return repository.addNotification(notification);
  }
}
