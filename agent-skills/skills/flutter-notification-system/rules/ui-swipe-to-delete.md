---
name: ui-swipe-to-delete
description: Use Flutter's Dismissible widget for swipe-to-delete on notification rows. Always call provider.deleteNotification() in onDismissed, show a SnackBar with Undo, and handle confirmDismiss for immediate visual feedback.
impact: HIGH
---

# Swipe-to-Delete Notification Pattern

## Context

`NotificationsPage` shows notification tiles but swipe-to-delete is not wired to `NotificationProvider.deleteNotification()`. `Dismissible` is the correct Flutter pattern — it handles the slide-out animation, removes the item from the list, and lets you offer an Undo snack bar.

## Correct Implementation

```dart
// features/notifications/presentation/widgets/notification_tile.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../domain/entities/notification_entity.dart';
import '../providers/notification_provider.dart';

class DismissibleNotificationTile extends StatelessWidget {
  final NotificationEntity notification;

  const DismissibleNotificationTile({
    super.key,
    required this.notification,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey(notification.id),  // must be unique per item

      // Only allow end-to-start (right swipe reveal delete)
      direction: DismissDirection.endToStart,

      // Red delete background revealed on swipe
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade400,
        child: const Icon(Icons.delete_outline, color: Colors.white, size: 26),
      ),

      // Ask for confirmation before animation completes
      confirmDismiss: (direction) async {
        // Return true immediately — undo is offered via SnackBar
        return true;
      },

      onDismissed: (direction) {
        final provider = context.read<NotificationProvider>();
        provider.deleteNotification(notification.id);

        // Offer undo
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Notification removed'),
            duration: const Duration(seconds: 3),
            action: SnackBarAction(
              label: 'Undo',
              onPressed: () {
                // Re-insert notification
                provider.undoDelete(notification);
              },
            ),
          ),
        );
      },

      child: NotificationTile(notification: notification),
    );
  }
}
```

## Add undoDelete to NotificationProvider

```dart
// features/notifications/presentation/providers/notification_provider.dart
// Add this method:

/// Temporarily removed item for undo support
NotificationEntity? _lastDeleted;

Future<void> deleteNotification(String id) async {
  _lastDeleted = _notifications.firstWhere((n) => n.id == id);
  _notifications.removeWhere((n) => n.id == id);
  notifyListeners();

  // Persist deletion (fire-and-forget — undo will re-insert)
  await _deleteNotificationUseCase(id);
}

Future<void> undoDelete(NotificationEntity notification) async {
  if (_lastDeleted?.id != notification.id) return;
  _notifications.insert(0, notification);
  _lastDeleted = null;
  notifyListeners();
  // Re-save to local cache
  // await _repository.saveNotification(notification);
}
```

## Usage in NotificationsPage ListView

```dart
// In _buildNotificationList():
ListView.builder(
  itemCount: notifications.length,
  itemBuilder: (ctx, i) => DismissibleNotificationTile(
    notification: notifications[i],
  ),
)
```

## Mark as Read on Tap

```dart
// NotificationTile.onTap:
onTap: () {
  if (!notification.isRead) {
    context.read<NotificationProvider>().markAsRead(notification.id);
  }
  // Navigate to relevant screen based on notification.type
}
```

## Incorrect Implementation

```dart
// Anti-pattern: Dismissible without ValueKey (causes rendering bugs on re-order)
Dismissible(
  key: UniqueKey(),  // ❌ new key every build — breaks dismiss animation
  child: tile,
)

// Anti-pattern: removing from list without Undo
onDismissed: (_) {
  setState(() { notifications.removeAt(index); });  // ❌ no undo, no provider call
}
```
