import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../../domain/entities/notification_entity.dart';

/// Notification Model for JSON serialization
class NotificationModel {
  final String id;
  final String type;
  final String title;
  final String body;
  final DateTime timestamp;
  final bool isRead;
  final Map<String, dynamic>? data;
  final String? iconIdentifier;
  final String? colorHex;

  NotificationModel({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.timestamp,
    required this.isRead,
    this.data,
    this.iconIdentifier,
    this.colorHex,
  });

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'type': type,
      'title': title,
      'body': body,
      'timestamp': timestamp.toIso8601String(),
      'isRead': isRead,
      'data': data,
      'iconIdentifier': iconIdentifier,
      'colorHex': colorHex,
    };
  }

  /// Create from JSON map
  factory NotificationModel.fromJson(Map<String, dynamic> json) {
    return NotificationModel(
      id: json['id'] as String,
      type: json['type'] as String,
      title: json['title'] as String,
      body: json['body'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String),
      isRead: json['isRead'] as bool? ?? false,
      data: json['data'] as Map<String, dynamic>?,
      iconIdentifier: json['iconIdentifier'] as String?,
      colorHex: json['colorHex'] as String?,
    );
  }

  /// Convert from entity
  factory NotificationModel.fromEntity(NotificationEntity entity) {
    return NotificationModel(
      id: entity.id,
      type: entity.type.name,
      title: entity.title,
      body: entity.body,
      timestamp: entity.timestamp,
      isRead: entity.isRead,
      data: entity.data,
      iconIdentifier: entity.iconIdentifier,
      colorHex: entity.colorHex,
    );
  }

  /// Convert to entity
  NotificationEntity toEntity() {
    return NotificationEntity(
      id: id,
      type: _parseType(type),
      title: title,
      body: body,
      timestamp: timestamp,
      isRead: isRead,
      data: data,
      iconIdentifier: iconIdentifier,
      colorHex: colorHex,
    );
  }

  NotificationType _parseType(String typeString) {
    return NotificationType.values.firstWhere(
      (t) => t.name == typeString,
      orElse: () => NotificationType.general,
    );
  }
}

/// Local data source interface for notifications
abstract class NotificationLocalDataSource {
  Future<List<NotificationEntity>> getNotifications();
  Future<void> saveNotifications(List<NotificationEntity> notifications);
  Future<void> addNotification(NotificationEntity notification);
  Future<void> markAsRead(String id);
  Future<void> markAllAsRead();
  Future<void> deleteNotification(String id);
  Future<void> deleteAllNotifications();
  Future<int> getUnreadCount();
  Future<NotificationEntity?> getNotificationById(String id);
}

/// Local data source implementation for notifications
/// Uses SharedPreferences for persistent storage
class NotificationLocalDataSourceImpl implements NotificationLocalDataSource {
  static const String _notificationsKey = 'notifications';
  static const int _maxNotifications = 100;

  SharedPreferences? _prefs;

  Future<SharedPreferences> get prefs async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  /// Get all notifications from local storage
  @override
  Future<List<NotificationEntity>> getNotifications() async {
    final p = await prefs;
    final jsonString = p.getString(_notificationsKey);
    if (jsonString == null || jsonString.isEmpty) {
      return [];
    }

    try {
      final List<dynamic> jsonList = json.decode(jsonString) as List<dynamic>;
      return jsonList
          .map((item) =>
              NotificationModel.fromJson(item as Map<String, dynamic>))
          .map((model) => model.toEntity())
          .toList()
        ..sort((a, b) => b.timestamp.compareTo(a.timestamp));
    } catch (e) {
      // If parsing fails, return empty list
      return [];
    }
  }

  /// Save notifications to local storage
  @override
  Future<void> saveNotifications(List<NotificationEntity> notifications) async {
    // Limit to max notifications
    final limitedList = notifications.take(_maxNotifications).toList();

    final models =
        limitedList.map((e) => NotificationModel.fromEntity(e)).toList();
    final jsonList = models.map((m) => m.toJson()).toList();
    final jsonString = json.encode(jsonList);

    final p = await prefs;
    await p.setString(_notificationsKey, jsonString);
  }

  /// Add a notification
  @override
  Future<void> addNotification(NotificationEntity notification) async {
    final notifications = await getNotifications();
    notifications.insert(0, notification);
    await saveNotifications(notifications);
  }

  /// Mark a notification as read
  @override
  Future<void> markAsRead(String id) async {
    final notifications = await getNotifications();
    final index = notifications.indexWhere((n) => n.id == id);
    if (index != -1) {
      notifications[index] = notifications[index].markAsRead();
      await saveNotifications(notifications);
    }
  }

  /// Mark all notifications as read
  @override
  Future<void> markAllAsRead() async {
    final notifications = await getNotifications();
    final updatedNotifications =
        notifications.map((n) => n.markAsRead()).toList();
    await saveNotifications(updatedNotifications);
  }

  /// Delete a notification
  @override
  Future<void> deleteNotification(String id) async {
    final notifications = await getNotifications();
    notifications.removeWhere((n) => n.id == id);
    await saveNotifications(notifications);
  }

  /// Delete all notifications
  @override
  Future<void> deleteAllNotifications() async {
    final p = await prefs;
    await p.remove(_notificationsKey);
  }

  /// Get unread count
  @override
  Future<int> getUnreadCount() async {
    final notifications = await getNotifications();
    return notifications.where((n) => !n.isRead).length;
  }

  /// Get notification by ID
  @override
  Future<NotificationEntity?> getNotificationById(String id) async {
    final notifications = await getNotifications();
    try {
      return notifications.firstWhere((n) => n.id == id);
    } catch (_) {
      return null;
    }
  }
}
