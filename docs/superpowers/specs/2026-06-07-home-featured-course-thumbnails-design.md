# Home Featured Course Thumbnails Design

## Goal

Show real course cover images in the Home featured-course cards using the same
deterministic fallback selection as the Course screens.

## Design

Extract the existing Course fallback-image selection into a shared presentation
helper. The helper selects an Unsplash image from course tags and level, using
the course ID hash to keep the result deterministic.

Featured-course cards try images in this order:

1. A non-empty backend `thumbnailUrl`.
2. The shared tag/level/ID fallback URL.
3. The existing colored school-icon placeholder.

Images use `CachedNetworkImage`. The current card size, gradient overlay, level
and XP badges, title, Hero animation, and navigation behavior remain unchanged.

## Scope

- Share the fallback resolver between Course and Home surfaces.
- Handle blank thumbnail URLs as missing data.
- Do not change backend schemas or API contracts.
- Do not add generated image assets to the application bundle.

## Verification

- Unit-test tag priority, level fallback, deterministic ID selection, and
  thumbnail candidate ordering.
- Run Dart formatting.
- Run focused Flutter tests.
- Run `flutter analyze`.
