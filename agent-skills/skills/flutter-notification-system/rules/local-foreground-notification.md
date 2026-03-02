---
name: local-foreground-notification
description: When a FCM message arrives while the app is in the foreground, Firebase does NOT automatically show a heads-up banner. Use flutter_local_notifications to display the notification manually inside FirebaseMessagingService._handleMessage().
impact: HIGH
---

# Foreground Notification Display (flutter_local_notifications)

## Context

`FirebaseMessaging.onMessage` fires when a message arrives while the app is open, but on Android it does **not** auto-show a heads-up banner — that only happens in the background. `NotificationService` (`lib/core/services/notification_service.dart`) already initialises `FlutterLocalNotificationsPlugin`. Use it inside `FirebaseMessagingService._handleMessage()`.

## Setup

```yaml
# pubspec.yaml (already present in LexiLingo)
dependencies:
  flutter_local_notifications: ^17.0.0
  firebase_messaging: ^15.0.0
```

## Correct Implementation

### Step 1: Create the notification channel constant

```dart
// lib/core/services/notification_service.dart — add constant
static const AndroidNotificationChannel highImportanceChannel =
    AndroidNotificationChannel(
  'lexilingo_high_importance',       // channel id
  'LexiLingo Notifications',         // name shown in system settings
  description: 'Streak reminders, review alerts, achievements',
  importance: Importance.high,       // shows heads-up banner
);
```

### Step 2: Create the channel on Android at startup

```dart
// In NotificationService.init()
await flutterLocalNotificationsPlugin
    .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>()
    ?.createNotificationChannel(highImportanceChannel);
```

### Step 3: Show notification in foreground handler

```dart
// lib/core/services/firebase_messaging_service.dart
// Inside _handleMessage(RemoteMessage message):

void _handleMessage(RemoteMessage message) {
  final notification = message.notification;
  if (notification == null) return;

  // Show local notification for in-app foreground display
  NotificationService().showFcmNotification(
    id: message.hashCode,
    title: notification.title ?? 'LexiLingo',
    body: notification.body ?? '',
    payload: message.data['route'] as String?, // deep-link target
  );

  // Also pass to provider stream (so notification list updates)
  _messageController.add(message);
}
```

### Step 4: Add showFcmNotification to NotificationService

```dart
// lib/core/services/notification_service.dart
Future<void> showFcmNotification({
  required int id,
  required String title,
  required String body,
  String? payload,
}) async {
  const androidDetails = AndroidNotificationDetails(
    'lexilingo_high_importance',
    'LexiLingo Notifications',
    channelDescription: 'Streak reminders, review alerts, achievements',
    importance: Importance.high,
    priority: Priority.high,
    showWhen: true,
  );

  const iosDetails = DarwinNotificationDetails(
    presentAlert: true,
    presentBadge: true,
    presentSound: true,
  );

  await flutterLocalNotificationsPlugin.show(
    id,
    title,
    body,
    const NotificationDetails(android: androidDetails, iOS: iosDetails),
    payload: payload,
  );
}
```

### Step 5: Handle notification tap (deep-link routing)

```dart
// In NotificationService.init() — add onDidReceiveNotificationResponse:
await flutterLocalNotificationsPlugin.initialize(
  initializationSettings,
  onDidReceiveNotificationResponse: (NotificationResponse response) {
    final payload = response.payload;
    if (payload != null) {
      // Route to appropriate screen
      // Use a GlobalKey<NavigatorState> or GoRouter navigateTo
      navigatorKey.currentState?.pushNamed(payload);
    }
  },
);
```

## Incorrect Implementation

```dart
// Anti-pattern: assuming Firebase shows a banner in foreground
FirebaseMessaging.onMessage.listen((message) {
  // ❌ Nothing visible to user on Android foreground
  debugPrint('Message received: ${message.notification?.title}');
});

// Anti-pattern: using Importance.low (no heads-up banner)
AndroidNotificationDetails('channel', 'Channel',
    importance: Importance.low,   // ❌ won't show heads-up
    priority: Priority.low);
```
