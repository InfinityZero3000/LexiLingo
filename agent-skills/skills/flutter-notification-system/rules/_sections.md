# Sections

This file defines all sections, their ordering, impact levels, and descriptions.

---

## 1. FCM Setup (fcm)

**Impact:** CRITICAL  
**Description:** Firebase Cloud Messaging setup: background handler with @pragma entry point, top-level function requirement, FirebaseMessaging.onBackgroundMessage registration in main().

## 2. Token Registration (token)

**Impact:** HIGH  
**Description:** FCM token lifecycle: initial registration with backend on login, token refresh handling, and unregistration on logout.

## 3. Local Notifications (local)

**Impact:** HIGH  
**Description:** flutter_local_notifications patterns for showing heads-up banners when a FCM message arrives while the app is in the foreground.

## 4. UI Patterns (ui)

**Impact:** HIGH  
**Description:** Swipe-to-delete with Dismissible, date-grouped notification list, empty state, and bottom navigation badge wiring.
