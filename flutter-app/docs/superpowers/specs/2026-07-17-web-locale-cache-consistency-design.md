# Web Locale Cache and Consistency Design

## Goal

Make Flutter Web load translations and language labels quickly, revalidate all deploy-owned assets on the first ordinary page load after each Vercel deployment, render CJK text without missing-glyph boxes, and guarantee that rapid locale changes cannot leave `context.locale`, loaded translations, and persisted settings on different languages.

## Constraints

- Web offline support is not required.
- Translation changes ship with the application deployment; runtime translation hot-reload is not required.
- Preserve the existing seven supported locales and optimistic settings UI.
- Do not add a cache framework, service worker, or new runtime dependency.
- Preserve unrelated work already present in the dirty worktree.

## Architecture

### Deployment cache policy

Use browser/CDN HTTP caching as the only web cache layer. Remove the custom service-worker update and cache-deletion script from `web/index.html`; current Flutter releases do not require a generated service worker for this non-offline application.

Vercel must revalidate entry points and every stable-name file whose contents can change between deployments:

- `index.html`
- `flutter_bootstrap.js`
- `main.dart.js`
- `version.json`
- Flutter asset manifests
- `assets/assets/i18n/*.json`
- stable-name font and image assets

These resources use `Cache-Control: no-cache` so the browser may reuse a response only after validating it. Do not use `no-store`, because revalidation retains fast conditional requests. Do not use `immutable` for stable URLs. A one-year immutable policy is reserved for filenames that contain a content hash; this project does not currently guarantee that for Flutter assets.

This policy intentionally does not replace code inside a tab that was already running when deployment occurred. The new build is guaranteed on the next navigation/page load through the entry point; no background version polling or forced reload is added.

### Translation loading

Replace `NetworkFirstAssetLoader` with EasyLocalization's bundled-asset loader. Locale changes read JSON from Flutter's already-loaded asset bundle instead of issuing an HTTP request with a timestamp. Delete the custom loader when no caller remains.

A deployment refreshes translation files through the Vercel revalidation policy. Translation selection itself remains local and therefore works quickly after application startup.

### Locale serialization

`LocaleService` becomes the sole writer of EasyLocalization locale state and the local locale preference. It owns one draining coordinator with at most one active request and one coalesced pending request. Each locale request:

1. Normalizes the requested language.
2. Replaces the pending request with the newest requested locale.
3. Waits for the active `setLocale` call to finish before applying the pending locale.
4. Persists only the locale that is still current after application.
5. Continues draining until no pending request remains.

Because only one `setLocale` operation can run at a time, its futures cannot mutate EasyLocalization out of order. Coalescing avoids loading intermediate locales that have not started. The locale applier and preference writer are injectable functions so the ordering can be tested without relying on EasyLocalization internals.

Each request returns a `Future<bool>`: `true` means that request became the applied/persisted locale; `false` means it was superseded before commit, whether pending or already active. Replacing a pending request immediately completes the replaced request with `false`, so no caller can hang. An active request superseded during its applier call completes `false` after that call returns, does not persist, and then drains the newest request. If active request A fails while newer request B is pending, A reports its error without rolling back B's optimistic state, and the drain continues to B. Only failure of the newest request may trigger provider rollback to the last fully applied and server-confirmed locale.

`SettingsProvider.updateLanguage` updates its in-memory selection optimistically and delegates locale application to `LocaleService`. Only a locale request that returns `true` may enqueue its language API write; superseded or failed locale requests never write stale language to the backend. Language API writes join `_settingsPersistenceQueue`, which currently serializes theme writes but not language writes. Each queued operation reads the latest intended settings at execution time and skips superseded language values. The provider tracks the last server-confirmed language. If the newest write fails, UI/local locale roll back to that confirmed language; failure of a superseded write cannot undo a newer choice. This keeps server, provider, EasyLocalization, and SharedPreferences convergent without concurrent repository writes.

The locale synchronization side effect in `main.dart` is removed. Settings loading may request one initial synchronization through the same `LocaleService` path, but widget rebuilds never call `setLocale`. Direct `context.setLocale` calls in application helpers are replaced or routed through `LocaleService` so there is one ordering authority.

### Fonts and flags

Bundle variable regular fonts for Noto Sans JP, Noto Sans KR, and Noto Sans SC and register their exact Flutter family names in `pubspec.yaml`. Keep the existing Lexend/Space Grotesk behavior for Latin text and use the bundled Noto families as CJK fallback. Remove the CJK Google Fonts stylesheet from `web/index.html`; global `google_fonts` runtime behavior is otherwise unchanged because Lexend and Space Grotesk are used broadly and replacing them is outside this fix.

Store the seven small flag images under application assets and render them with `Image.asset`. Remove network preloading and `CachedNetworkImage` usage for language flags. Other unrelated network images remain unchanged.

## Error handling

- Unsupported locale codes normalize to English as today.
- Locale application errors are surfaced to `SettingsProvider`; the latest active request rolls back to the prior consistent locale.
- Settings API failure does not roll back a newer language selection.
- Missing flag assets use the existing two-letter fallback.
- Flutter build validation covers declared font-file existence. A rendered web smoke check covers actual CJK glyphs and fallback family behavior.

## Verification

- Deterministically test the drain: hold active request A incomplete, issue B and C, assert neither starts while A is active and B completes as superseded; finish A, assert A also completes `false` without persistence, only C starts, and the final locale/preference is C.
- Test active A failure while B is pending: the drain must continue to B and A's failure must not roll back B's optimistic state.
- Test that a stale API failure cannot roll back a newer language.
- Test initial settings synchronization uses the same serialized locale coordinator.
- Build Flutter Web and inspect generated asset paths.
- Replace the overlapping broad immutable Vercel asset rule rather than layering a second `Cache-Control` value. Derive header matchers from the generated Web build and verify the effective response headers for `index.html`, SPA rewrite responses, bootstrap/entrypoint, every emitted asset/font manifest, CanvasKit/WASM resources when emitted, i18n, fonts, and flags. Verify both locally from configuration and against the deployed URL with `curl` after deployment.
- Render representative `中文`, `日本語`, and `한국어` strings in a Web smoke/widget check and confirm no missing-glyph boxes. Confirm a missing flag path reaches the existing fallback.
- Run focused Flutter tests and `flutter analyze`.
- Have `test-writer` add/confirm regression coverage after implementation and `code-reviewer` review the non-trivial final diff.

## Deliberate exclusions

- No offline/PWA service worker.
- No runtime translation CMS or background refresh.
- No new cache-version endpoint.
- No abstraction beyond the existing `LocaleService` and `SettingsProvider` boundaries.
