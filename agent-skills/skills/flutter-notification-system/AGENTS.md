# LexiLingo Team - Flutter Notification System

**Version 1.0.0**  
LexiLingo Team  
March 2026

> **Note:**  
> This document is mainly for agents and LLMs to follow when maintaining,  
> generating, or refactoring code. Humans may also find it useful, but guidance  
> here is optimized for automation and consistency by AI-assisted workflows.

---

## Abstract

Firebase Cloud Messaging integration patterns for LexiLingo Flutter app. Covers FCM background message handler (@pragma entry point), FCM token registration with the backend device API, flutter_local_notifications foreground display, Dismissible swipe-to-delete pattern, and notification badge on the bottom navigation bar. The notification domain/data/provider layers are already implemented — these rules fill the remaining integration gaps.

---

## Table of Contents

1. [FCM Setup](##1-fcm-setup)
2. [Token Registration](##2-token-registration)
3. [Local Notifications](##3-local-notifications)
4. [UI Patterns](##4-ui-patterns)

---

## 1. FCM Setup

**Impact: CRITICAL**

Firebase Cloud Messaging setup: background handler with @pragma entry point, top-level function requirement, FirebaseMessaging.onBackgroundMessage registration in main().

### 1.1 Untitled

**Impact: CRITICAL**



---

## 2. Token Registration

**Impact: HIGH**

FCM token lifecycle: initial registration with backend on login, token refresh handling, and unregistration on logout.

### 2.1 Untitled

**Impact: HIGH**



---

## 3. Local Notifications

**Impact: HIGH**

flutter_local_notifications patterns for showing heads-up banners when a FCM message arrives while the app is in the foreground.

### 3.1 Untitled

**Impact: HIGH**



---

## 4. UI Patterns

**Impact: HIGH**

Swipe-to-delete with Dismissible, date-grouped notification list, empty state, and bottom navigation badge wiring.

### 4.1 Untitled

**Impact: HIGH**



---

## References

1. [https://firebase.flutter.dev/docs/messaging/usage/](https://firebase.flutter.dev/docs/messaging/usage/)
2. [https://firebase.flutter.dev/docs/messaging/notifications/](https://firebase.flutter.dev/docs/messaging/notifications/)
3. [https://pub.dev/packages/flutter_local_notifications](https://pub.dev/packages/flutter_local_notifications)
4. [https://pub.dev/packages/firebase_messaging](https://pub.dev/packages/firebase_messaging)
