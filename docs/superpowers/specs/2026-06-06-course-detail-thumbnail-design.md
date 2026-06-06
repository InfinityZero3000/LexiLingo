# Course Detail Thumbnail Design

## Goal

Display the same course image on the course detail screen that the learner saw
on the course card, including generated fallback images when the API does not
provide `thumbnail_url`.

## Design

The course list resolves one display URL for each card. Navigation passes that
resolved URL to `CourseDetailScreen` as optional initial presentation data.
The detail screen still loads authoritative course data from the existing
course-detail API.

The detail hero tries images in this order:

1. The detail API `thumbnail_url`.
2. The resolved image passed by the source course card.
3. The existing colored school-icon placeholder.

Duplicate and blank URLs are ignored. Network images use
`CachedNetworkImage`, preserving the existing `BoxFit.cover`, rounded shape,
shadow, gradient overlay, and Hero animation.

## Scope

- Update the discovery course list and category detail navigation paths that
  already render course thumbnails.
- Keep callers without course image context source-compatible.
- Do not change backend schemas or API contracts.

## Verification

- Unit-test URL priority and blank/duplicate filtering.
- Run Dart formatting.
- Run focused Flutter tests.
- Run `flutter analyze`.
