# Roadmap Numbering Consistency Design

## Goal

Keep course-detail and full-roadmap screens consistent even when stored
`order_index` values are zero-based, one-based, sparse, or otherwise non-contiguous.

## Business Rules

- `order_index` controls sorting only.
- Display numbers are one-based ordinals after sorting.
- The first displayed unit and lesson are numbered 1.
- Lesson locking follows the previous lesson in sorted order, not numeric
  adjacency between `order_index` values.
- Unit titles, descriptions, colors, lessons, and totals continue to come from
  the same persisted course data.

## Data Flow

The course-detail endpoint returns units sorted by `order_index`; Flutter
already labels those units with `index + 1`. The learning-roadmap endpoint
must apply the same rule while building `unit_number` and `lesson_number`.
This makes the backend response stable for every client without requiring
database migrations.

## Testing

Endpoint tests will assert that returned unit and lesson numbers are
contiguous and one-based according to response order. Existing lock-state
coverage will continue to verify that the first lesson is available.

