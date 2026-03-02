---
name: fcm-background-handler
description: Firebase background message handler MUST be a top-level function annotated with @pragma('vm:entry-point'). Registered via FirebaseMessaging.onBackgroundMessage() in main() BEFORE runApp(). Missing pragma causes silent failures in release builds.
impact: CRITICAL
---

# FCM Background/Terminated Message Handler

## Context

`FirebaseMessagingService` in `lib/core/services/firebase_messaging_service.dart` handles foreground messages. Background and terminated-state messages require a **separate top-level handler** registered before `runApp()`. Missing `@pragma('vm:entry-point')` causes the handler to be tree-shaken in release/profile builds, resulting in silent notification failures.

## Rule

1. Define a top-level function (not a class method, not a closure) annotated with `@pragma('vm:entry-point')`
2. Call `FirebaseMessaging.onBackgroundMessage(handleBackgroundMessage)` in `main()` before `WidgetsFlutterBinding.ensureInitialized()` or at minimum before `runApp()`
3. The handler must complete quickly; heavy processing should be deferred

## Correct Implementation

```dart
// lib/main.dart

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

// ⚠️ MUST be a TOP-LEVEL function — not a class method
// ⚠️ MUST have @pragma annotation for release build tree-shaking prevention
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Firebase must be initialized in the handler if it uses other Firebase services
  // await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  debugPrint('🔔 Background FCM message received: ${message.messageId}');
  debugPrint('   Title: ${message.notification?.title}');
  debugPrint('   Body:  ${message.notification?.body}');
  debugPrint('   Data:  ${message.data}');

  // Save to local storage so it appears when user opens app
  // Use a lightweight storage call — avoid full provider/DI init here
  // final prefs = await SharedPreferences.getInstance();
  // (append message id to a pending list, then sync in NotificationProvider._init())
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Register BEFORE runApp
  FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  // ... rest of initialization
  runApp(const LexiLingoApp());
}
```

## iOS Background Modes (Info.plist)

For iOS, ensure `UIBackgroundModes` includes `remote-notification` in `ios/Runner/Info.plist`:

```xml
<key>UIBackgroundModes</key>
<array>
  <string>fetch</string>
  <string>remote-notification</string>
</array>
```

## Android Notification Channel (Android 8+)

```dart
// In FirebaseMessagingService.initialize() or NotificationService.init()
if (Platform.isAndroid) {
  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(
        const AndroidNotificationChannel(
          'lexilingo_high_importance',
          'LexiLingo Notifications',
          description: 'Learning reminders and streak alerts',
          importance: Importance.high,
        ),
      );
}
```

## Incorrect Implementation

```dart
// Anti-pattern: handler inside a class (won't work as background handler)
class FirebaseMessagingService {
  Future<void> _backgroundHandler(RemoteMessage message) async { ... }  // ❌

  void setup() {
    FirebaseMessaging.onBackgroundMessage(_backgroundHandler); // ❌ won't work
  }
}

// Anti-pattern: missing @pragma (tree-shaken in release builds)
Future<void> handleBackground(RemoteMessage message) async { ... }  // ❌ no @pragma

// Anti-pattern: registering after runApp
runApp(const App()); // ❌ should register before this
FirebaseMessaging.onBackgroundMessage(handler);
```
