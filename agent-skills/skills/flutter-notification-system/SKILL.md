---
name: lexilingo-flutter-notification-system
description: Firebase Cloud Messaging integration patterns for LexiLingo. The domain/data/provider layers already exist — use this skill to correctly wire up the FCM background handler, register tokens with the backend device API, display foreground notifications via flutter_local_notifications, implement Dismissible swipe-to-delete, and show the unread badge on the bottom navigation bar.
license: MIT
metadata:
  author: LexiLingo Team
  version: "1.0.0"
---

# Flutter Notification System Integration

The notification feature structure (`features/notifications/`) is already implemented. These rules cover the remaining integration gaps that are easy to get wrong.

## Current State (as of March 2026)

| Component | Status |
|-----------|--------|
| `NotificationEntity` | ✅ Done — `features/notifications/domain/entities/` |
| `NotificationRepository` (interface) | ✅ Done |
| `NotificationRepositoryImpl` | ✅ Done — uses `SharedPreferences` local cache |
| `NotificationProvider` | ✅ Done — streams `unreadCount`, `groupedNotifications` |
| `NotificationsPage` | ✅ Done |
| `FirebaseMessagingService` | ✅ Done — foreground message listener |
| **FCM background handler** | ❌ Missing `@pragma` entry point |
| **FCM token → backend** | ❌ Token not sent to `/api/devices` |
| **Foreground local notification** | ❌ In-app heads-up not displayed |
| **Swipe-to-delete** | ⚠️ UI only — not wired to provider |
| **Bottom nav badge** | ✅ Done — `notificationProvider.unreadCount` |

## When to Apply

Use this skill when:
- Wiring up FCM background/terminated message handling
- Registering the FCM token with the backend after login
- Displaying a heads-up notification when a message arrives while app is open
- Implementing swipe-to-delete on `NotificationsPage`
- Debugging missing notifications on iOS (permission flow)

## Rule Categories by Priority

| Priority | Category | Impact | Prefix |
|----------|----------|--------|--------|
| 1 | FCM Setup | CRITICAL | `fcm-` |
| 2 | Token Registration | HIGH | `token-` |
| 3 | Local Notifications | HIGH | `local-` |
| 4 | UI Patterns | HIGH | `ui-` |
