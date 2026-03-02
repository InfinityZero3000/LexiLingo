# Sections

This file defines all sections, their ordering, impact levels, and descriptions.

---

## 1. Loading States (loading)

**Impact:** HIGH  
**Description:** Shimmer skeleton patterns for loading states. Replace static spinners with content-shaped skeletons to reduce perceived lag.

## 2. List Animation (list)

**Impact:** HIGH  
**Description:** Staggered entry animations for lists and grids. Items slide in with an offset and fade to signal fresh content loading.

## 3. Navigation (nav)

**Impact:** HIGH  
**Description:** Hero transitions between list items and detail screens. Provides spatial continuity and signals navigable elements.

## 4. Celebration (celebrate)

**Impact:** MEDIUM  
**Description:** Rewarding feedback animations for milestones like level-up and streak achievement. Should be brief, joyful, and dismissible.

## 5. Performance (perf)

**Impact:** HIGH  
**Description:** Guidelines for keeping all animations at 60fps: using RepaintBoundary, avoiding layout thrashing inside AnimatedBuilder, and choosing the right animation type.
