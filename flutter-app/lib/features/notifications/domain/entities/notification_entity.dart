import 'package:equatable/equatable.dart';

/// Notification types supported by the app
enum NotificationType {
  /// Reminder to complete daily learning
  streakReminder,

  /// Reminder to start a lesson
  lessonReminder,

  /// Achievement unlocked
  achievement,

  /// New content available
  newContent,

  /// Weekly summary ready
  weeklySummary,

  /// Social interaction (friend activity)
  social,

  /// System notification
  system,

  /// General notification
  general,
}

/// Notification Entity
/// Represents a single notification in the app
class NotificationEntity extends Equatable {
  /// Unique identifier for the notification
  final String id;

  /// Type of notification for categorization and handling
  final NotificationType type;

  /// Notification title
  final String title;

  /// Notification body/message
  final String body;

  /// Timestamp when notification was created/received
  final DateTime timestamp;

  /// Whether the notification has been read
  final bool isRead;

  /// Additional data associated with the notification
  /// Can contain targetId, route, etc.
  final Map<String, dynamic>? data;

  /// Icon identifier for display
  final String? iconIdentifier;

  /// Color hex for the notification icon background
  final String? colorHex;

  const NotificationEntity({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    this.isRead = false,
    this.data,
    this.iconIdentifier,
    this.colorHex,
  });

  /// Create a copy with updated fields
  NotificationEntity copyWith({
    String? id,
    NotificationType? type,
    String? title,
    String? body,
    DateTime? timestamp,
    bool? isRead,
    Map<String, dynamic>? data,
    String? iconIdentifier,
    String? colorHex,
  }) {
    return NotificationEntity(
      id: id ?? this.id,
      type: type ?? this.type,
      title: title ?? this.title,
      body: body ?? this.body,
      timestamp: timestamp ?? this.timestamp,
      isRead: isRead ?? this.isRead,
      data: data ?? this.data,
      iconIdentifier: iconIdentifier ?? this.iconIdentifier,
      colorHex: colorHex ?? this.colorHex,
    );
  }

  /// Mark notification as read
  NotificationEntity markAsRead() {
    return copyWith(isRead: true);
  }

  /// Check if notification is from today
  bool get isToday {
    final now = DateTime.now();
    return timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
  }

  /// Check if notification is from yesterday
  bool get isYesterday {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return timestamp.year == yesterday.year &&
        timestamp.month == yesterday.month &&
        timestamp.day == yesterday.day;
  }

  /// Get relative time string (e.g., "2m ago", "1h ago", "Yesterday")
  String get relativeTimeString {
    final now = DateTime.now();
    final difference = now.difference(timestamp);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (isYesterday) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${timestamp.day}/${timestamp.month}/${timestamp.year}';
    }
  }

  /// Get target ID from data if available
  String? get targetId => data?['target_id'] as String?;

  /// Get route from data if available
  String? get route => data?['route'] as String?;

  /// Factory for creating notification from FCM message
  factory NotificationEntity.fromFcm({
    required String id,
    required String title,
    required String body,
    Map<String, dynamic>? data,
  }) {
    final typeString = data?['type'] as String?;
    final type = _parseNotificationType(typeString);

    return NotificationEntity(
      id: id,
      type: type,
      title: title,
      body: body,
      timestamp: DateTime.now(),
      isRead: false,
      data: data,
      iconIdentifier: _getIconForType(type),
      colorHex: _getColorForType(type),
    );
  }

  /// Parse notification type from string
  static NotificationType _parseNotificationType(String? typeString) {
    switch (typeString) {
      case 'streak_reminder':
        return NotificationType.streakReminder;
      case 'lesson_reminder':
        return NotificationType.lessonReminder;
      case 'achievement':
        return NotificationType.achievement;
      case 'new_content':
        return NotificationType.newContent;
      case 'weekly_summary':
        return NotificationType.weeklySummary;
      case 'social':
        return NotificationType.social;
      case 'system':
        return NotificationType.system;
      default:
        return NotificationType.general;
    }
  }

  /// Get icon identifier for notification type
  static String _getIconForType(NotificationType type) {
    switch (type) {
      case NotificationType.streakReminder:
        return 'local_fire_department';
      case NotificationType.lessonReminder:
        return 'schedule';
      case NotificationType.achievement:
        return 'emoji_events';
      case NotificationType.newContent:
        return 'new_releases';
      case NotificationType.weeklySummary:
        return 'menu_book';
      case NotificationType.social:
        return 'people';
      case NotificationType.system:
        return 'info';
      case NotificationType.general:
        return 'notifications';
    }
  }

  /// Get color hex for notification type
  static String _getColorForType(NotificationType type) {
    switch (type) {
      case NotificationType.streakReminder:
        return '#FF9800'; // Orange
      case NotificationType.lessonReminder:
        return '#2196F3'; // Blue
      case NotificationType.achievement:
        return '#FFD700'; // Gold
      case NotificationType.newContent:
        return '#4CAF50'; // Green
      case NotificationType.weeklySummary:
        return '#9C27B0'; // Purple
      case NotificationType.social:
        return '#00BCD4'; // Cyan
      case NotificationType.system:
        return '#607D8B'; // Blue Grey
      case NotificationType.general:
        return '#2196F3'; // Blue
    }
  }

  @override
  List<Object?> get props => [
        id,
        type,
        title,
        body,
        timestamp,
        isRead,
        data,
        iconIdentifier,
        colorHex,
      ];
}

/// Notification group for displaying in sections
class NotificationGroup {
  final String title;
  final List<NotificationEntity> notifications;

  const NotificationGroup({
    required this.title,
    required this.notifications,
  });

  /// Check if group has any unread notifications
  bool get hasUnread => notifications.any((n) => !n.isRead);

  /// Get count of unread notifications in this group
  int get unreadCount => notifications.where((n) => !n.isRead).length;
}
