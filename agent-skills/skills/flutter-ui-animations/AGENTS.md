# LexiLingo Team - Flutter Ui Animations

**Version 1.0.0**  
LexiLingo Team  
March 2026

> **Note:**  
> This document is mainly for agents and LLMs to follow when maintaining,  
> generating, or refactoring code. Humans may also find it useful, but guidance  
> here is optimized for automation and consistency by AI-assisted workflows.

---

## Abstract

Animation patterns for LexiLingo Flutter app. Covers shimmer loading effects, staggered list animations, Hero course-card transitions, pull-to-refresh with custom animation, and the Level-Up celebration dialog. Use when implementing UI polish tasks: staggered home page loading, course card heroes, shimmer skeletons, and XP/level-up feedback.

---

## Table of Contents

1. [Loading States](##1-loading-states)
2. [List Animation](##2-list-animation)
3. [Navigation](##3-navigation)
4. [Celebration](##4-celebration)

---

## 1. Loading States

**Impact: HIGH**

Shimmer skeleton patterns for loading states. Replace static spinners with content-shaped skeletons to reduce perceived lag.

### 1.1 Untitled

**Impact: HIGH**



---

## 2. List Animation

**Impact: HIGH**

Staggered entry animations for lists and grids. Items slide in with an offset and fade to signal fresh content loading.

### 2.1 Untitled

**Impact: HIGH**



---

## 3. Navigation

**Impact: HIGH**

Hero transitions between list items and detail screens. Provides spatial continuity and signals navigable elements.

### 3.1 Untitled

**Impact: HIGH**



---

## 4. Celebration

**Impact: MEDIUM**

Rewarding feedback animations for milestones like level-up and streak achievement. Should be brief, joyful, and dismissible.

### 4.1 Untitled

**Impact: MEDIUM**



---

## References

1. [https://docs.flutter.dev/ui/animations](https://docs.flutter.dev/ui/animations)
2. [https://pub.dev/packages/shimmer](https://pub.dev/packages/shimmer)
3. [https://docs.flutter.dev/cookbook/animation/staggered-menu-animation](https://docs.flutter.dev/cookbook/animation/staggered-menu-animation)
4. [https://pub.dev/packages/lottie](https://pub.dev/packages/lottie)
