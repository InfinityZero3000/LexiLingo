# Language Flag Preload Design

## Goal

Preload all supported language flags when LexiLingo starts so the Settings
language selector does not briefly show broken image boxes.

## Design

- Add a small shared flag image cache service under `core/services`.
- Start a best-effort preload after the first app frame so startup rendering is
  not blocked.
- Use `CachedNetworkImage` in Settings, matching the provider used by preload.
- Keep a neutral placeholder while loading and a country-code fallback when a
  flag cannot be downloaded.

## Verification

- Unit-test that preload covers every supported locale and generates the
  expected FlagCDN URLs.
- Run Flutter formatting, focused tests, and static analysis.
