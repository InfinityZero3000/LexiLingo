# Sections

This file defines all sections, their ordering, impact levels, and descriptions.
The section ID (in parentheses) is the filename prefix used to group rules.

---

## 1. Domain Layer (domain)

**Impact:** CRITICAL  
**Description:** Entities, repository interfaces, and use cases that are 100% independent of Flutter, HTTP, or database frameworks. These are the stable core of each feature.

## 2. Data Layer (data)

**Impact:** HIGH  
**Description:** API models (with fromJson), data sources (remote + local), and repository implementations that wire everything together.

## 3. Presentation Layer (presentation)

**Impact:** HIGH  
**Description:** Provider-based state management, screen-level widgets, and the contract between UI and domain layer.

## 4. Error Handling (error)

**Impact:** HIGH  
**Description:** Typed failure objects, exception-to-failure mapping, and patterns for propagating errors to the UI without leaking implementation details.
