---
name: presentation-provider-pattern
description: Use ChangeNotifier providers for feature state. Always expose isLoading, error, and data triad. Never import data models directly in widgets.
impact: HIGH
---

# Presentation Provider Pattern (ChangeNotifier)

## Rule

Each feature has a `<Feature>Provider` in `features/<feature>/presentation/providers/`. It:
1. Extends `ChangeNotifier`
2. Exposes `isLoading`, `error` (String?), and the typed data list/object
3. Calls domain use cases — never repositories or data sources directly
4. Calls `notifyListeners()` after each state change
5. Must be registered in `main.dart` via `MultiProvider`

## Correct Implementation

```dart
// features/notifications/presentation/providers/notification_provider.dart
import 'package:flutter/foundation.dart';
import '../../domain/entities/notification_entity.dart';
import '../../domain/usecases/get_notifications.dart';
import '../../domain/usecases/mark_as_read.dart';
import '../../domain/usecases/mark_all_as_read.dart';
import '../../domain/usecases/delete_notification.dart';
import 'dart:async';

class NotificationProvider extends ChangeNotifier {
  final GetNotifications _getNotifications;
  final MarkAsRead _markAsRead;
  final MarkAllAsRead _markAllAsRead;
  final DeleteNotification _deleteNotification;
  StreamSubscription? _incomingSubscription;

  NotificationProvider({
    required GetNotifications getNotifications,
    required MarkAsRead markAsRead,
    required MarkAllAsRead markAllAsRead,
    required DeleteNotification deleteNotification,
  })  : _getNotifications = getNotifications,
        _markAsRead = markAsRead,
        _markAllAsRead = markAllAsRead,
        _deleteNotification = deleteNotification;

  // ---- State ----
  List<NotificationEntity> _notifications = [];
  bool _isLoading = false;
  String? _error;

  // ---- Getters ----
  List<NotificationEntity> get notifications => List.unmodifiable(_notifications);
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get unreadCount => _notifications.where((n) => !n.isRead).length;

  // ---- Actions ----
  Future<void> loadNotifications() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await _getNotifications();
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
      },
      (data) {
        _notifications = data;
        _isLoading = false;
      },
    );
    notifyListeners();
  }

  Future<void> markAsRead(String id) async {
    final result = await _markAsRead(id);
    result.fold(
      (failure) => _error = failure.message,
      (updated) {
        final idx = _notifications.indexWhere((n) => n.id == id);
        if (idx != -1) _notifications[idx] = updated;
      },
    );
    notifyListeners();
  }

  Future<void> markAllAsRead() async {
    final result = await _markAllAsRead();
    result.fold(
      (failure) => _error = failure.message,
      (_) {
        _notifications = _notifications.map((n) => n.copyWith(isRead: true)).toList();
      },
    );
    notifyListeners();
  }

  Future<void> deleteNotification(String id) async {
    final result = await _deleteNotification(id);
    result.fold(
      (failure) => _error = failure.message,
      (_) => _notifications.removeWhere((n) => n.id == id),
    );
    notifyListeners();
  }

  /// Wire up real-time FCM stream
  void listenForNewNotifications(Stream<NotificationEntity> stream) {
    _incomingSubscription?.cancel();
    _incomingSubscription = stream.listen((notification) {
      _notifications.insert(0, notification);
      notifyListeners();
    });
  }

  @override
  void dispose() {
    _incomingSubscription?.cancel();
    super.dispose();
  }
}
```

## Usage in Widget

```dart
// In widget — only import the provider and entity
final provider = context.watch<NotificationProvider>();

if (provider.isLoading) return const ShimmerNotificationList();
if (provider.error != null) return ErrorWidget(provider.error!);
if (provider.notifications.isEmpty) return const EmptyNotificationsWidget();

return ListView.builder(
  itemCount: provider.notifications.length,
  itemBuilder: (ctx, i) => NotificationTile(
    notification: provider.notifications[i],
    onTap: () => provider.markAsRead(provider.notifications[i].id),
  ),
);
```

## Incorrect Implementation

```dart
// Anti-pattern: calling repository directly from widget
class MyWidget extends StatelessWidget {
  final NotificationRepository repo; // ❌ bypass provider

  Future<void> _load() async {
    final data = await repo.getNotifications(); // ❌
  }
}

// Anti-pattern: no loading state tracking
class NotificationProvider extends ChangeNotifier {
  Future<void> load() async {
    _notifications = await _repo.getNotifications(); // ❌ no isLoading flag
    notifyListeners();
  }
}
```
