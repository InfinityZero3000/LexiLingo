# Fixed Points Calendar Height Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep the points calendar card at a stable six-row height while navigating between months.

**Architecture:** Preserve the existing `GridView.count` and its date-cell behavior. Pad the generated cell list with trailing empty widgets until it always contains 42 cells.

**Tech Stack:** Flutter, Dart, Material widgets

---

## Chunk 1: Fixed Calendar Grid

### Task 1: Pad the calendar to six rows

**Files:**
- Modify: `flutter-app/lib/features/progress/presentation/widgets/points_calendar_dialog.dart`

- [x] **Step 1: Add the fixed grid size**

Add a private constant for six rows by seven columns:

```dart
const _kCalendarCellCount = 42;
```

- [x] **Step 2: Add trailing empty cells**

After generating all date cells in `_buildDaysGrid`, append empty widgets until
the list reaches `_kCalendarCellCount`.

```dart
while (cells.length < _kCalendarCellCount) {
  cells.add(const SizedBox.shrink());
}
```

- [x] **Step 3: Format the modified file**

Run:

```bash
dart format lib/features/progress/presentation/widgets/points_calendar_dialog.dart
```

Expected: the file is formatted successfully.

- [x] **Step 4: Run static analysis**

Run:

```bash
flutter analyze lib/features/progress/presentation/widgets/points_calendar_dialog.dart
```

Expected: no new analyzer errors.

- [x] **Step 5: Review the final diff**

Confirm the diff only adds the 42-cell constant and trailing empty cells, and
does not alter date styling, month navigation, or reminder behavior.
