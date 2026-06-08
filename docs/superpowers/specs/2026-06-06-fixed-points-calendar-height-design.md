# Fixed Points Calendar Height Design

## Goal

Keep the attendance calendar card at a stable height when users move between
months with different week counts.

## Current Behavior

The day grid only creates cells for the leading offset and the days in the
selected month. Because `GridView.count` uses `shrinkWrap`, months spanning
four, five, or six calendar rows produce different grid and card heights. The
reminder section below therefore moves vertically when the month changes.

## Design

The calendar uses a Sunday-first layout with seven columns. After adding the
leading empty cells and day cells, append trailing empty cells until the grid
contains exactly 42 cells: six rows by seven columns.

This fixes the height of the day grid at the maximum month layout while leaving
the reminder section and the outer dialog content-driven. Months requiring
fewer than six rows display empty space after their final day.

No date calculations, check-in styling, navigation, reminder behavior, colors,
or typography will change.

## Implementation Scope

Modify only:

- `flutter-app/lib/features/progress/presentation/widgets/points_calendar_dialog.dart`

In `_buildDaysGrid`, fill the remaining positions with empty widgets until
`cells.length == 42`.

## Validation

- A four-row month renders six grid rows.
- A five-row month renders six grid rows.
- A six-row month renders six grid rows without losing any date.
- Moving between those months does not move the reminder section.
- Flutter static analysis reports no new issue in the modified file.

## Risks

The dialog becomes slightly taller for shorter months. The outer dialog remains
content-driven, so enabling the reminder time row continues to work as before.
