# Web Locale Cache and Consistency Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make deployed Web assets revalidate on a normal page load, make locale selection local and fast, remove CJK missing glyphs, and make rapid language changes last-request-wins across EasyLocalization, preferences, provider state, and the backend.

**Architecture:** HTTP revalidation replaces the custom Web service-worker/cache-busting paths. `LocaleService` owns a single coalescing drain so only one `setLocale` runs at a time; `SettingsProvider` writes the backend only for the locale request that actually commits. CJK fonts and the seven flags are build assets.

**Tech Stack:** Flutter, EasyLocalization, Provider, SharedPreferences, Vercel headers, Flutter widget/unit tests.

---

## Chunk 1: Ordered locale state

### Task 1: Add a coalescing locale drain

**Files:**
- Modify: `lib/core/services/locale_service.dart`
- Create: `test/core/services/locale_service_test.dart`

- [ ] **Step 1: Write failing drain tests**

Add tests with injected locale-applier and preference-writer callbacks. The exact test API is `debugConfigure({required apply, required persist})`, `debugRequestLocale(code)`, and `debugReset()` in `tearDown`:

```dart
test('serializes application and coalesces pending locales', () async {
  final ja = Completer<void>();
  final started = <String>[];
  final persisted = <String>[];
  LocaleService.debugConfigure(
    apply: (code) {
      started.add(code);
      return code == 'ja' ? ja.future : Future.value();
    },
    persist: (code) async => persisted.add(code),
  );

  final first = LocaleService.debugRequestLocale('ja');
  final second = LocaleService.debugRequestLocale('ko');
  final third = LocaleService.debugRequestLocale('en');

  expect(started, ['ja']);
  expect(await second, isFalse);
  ja.complete();
  expect(await first, isFalse);
  expect(await third, isTrue);
  expect(started, ['ja', 'en']);
  expect(persisted, ['en']);
});
```

Also test that failure of any started applier completes that request with its original error while still continuing to drain the newest pending locale. Reserve `false` for a replaced pending request or an active request that applied successfully but was superseded before commit. Call `LocaleService.debugReset()` in `tearDown` so static state cannot leak between tests.

- [ ] **Step 2: Verify tests fail**

Run: `flutter test test/core/services/locale_service_test.dart`

Expected: FAIL because the coordinator/test hooks do not exist.

- [ ] **Step 3: Implement the minimum coordinator**

Keep the public context-based entry point, and add one internal request record containing a monotonic ID, code, applier, and `Completer<bool>`; keep one active request and one replaceable pending request. Use `Completer<bool>`; complete replaced pending requests with `false`. After an active apply finishes, persist only if its ID is still newest, complete it with `true`, otherwise complete `false`, then drain the newest pending request. Any started applier error uses `completeError` with its original stack trace, while `finally` still clears active state and starts the newest pending request.

Production application remains:

```dart
static Future<bool> updateAppLocale(
  BuildContext context,
  String languageCode,
) => requestLocale(
  languageCode,
  apply: (code) => context.setLocale(Locale(code)),
);
```

`debugConfigure` replaces the default applier and preference writer, `debugRequestLocale` enters the same queue without a `BuildContext`, and `debugReset` clears callbacks, IDs, active/pending state after asserting no active request remains. Expose them with `@visibleForTesting`; do not introduce a new package or service interface. `saveLocale` remains the production preference writer but no caller may invoke it as a fallback around the queue.

- [ ] **Step 4: Run focused tests**

Run: `flutter test test/core/services/locale_service_test.dart`

Expected: PASS.

- [ ] **Step 5: Inspect the focused diff**

Run: `git diff -- lib/core/services/locale_service.dart test/core/services/locale_service_test.dart`

Expected: only coordinator and regression-test changes.

### Task 2: Route provider persistence through the committed locale

**Files:**
- Modify: `lib/features/user/presentation/providers/settings_provider.dart`
- Modify: `test/features/user/presentation/providers/settings_provider_theme_test.dart`

- [ ] **Step 1: Add failing provider regressions**

Cover:

1. A superseded locale result does not call `updateSettings`.
2. Rapid language selections result in one final backend write for the last committed locale.
3. Failure of an obsolete request does not roll back the newest optimistic language.
4. Failure of the newest backend write rolls back to the last server-confirmed language and requests that locale through `LocaleService`.
5. Failure of the newest locale application rolls back without writing the backend.
6. A theme update interleaved with rapid language choices cannot write an older theme or language snapshot after the final combined settings state.

Extend the fake repository to record every updated language and allow queued completers rather than a single shared completer.

- [ ] **Step 2: Verify tests fail**

Run: `flutter test test/features/user/presentation/providers/settings_provider_theme_test.dart`

Expected: at least the rapid-language tests FAIL because `updateLanguage` writes directly and rolls back per request.

- [ ] **Step 3: Implement gated serialized persistence**

In `updateLanguage`:

- set the optimistic language and notify;
- await `LocaleService.updateAppLocale`;
- return without API persistence when it returns `false`;
- append the backend operation to `_settingsPersistenceQueue`;
- at queue execution time, merge the operation's intended field into the latest `_settings` instead of sending a stale whole-object snapshot;
- skip a language operation whose language is no longer the provider's selected language;
- track `_confirmedLanguage` after settings load and successful language backend writes;
- roll back only when the failed language is still selected.

Only a successful queued language operation advances `_confirmedLanguage`; a successful theme operation that happens to merge the current optimistic language must not confirm it. Assert this in the theme/language interleaving test. When locale application throws, roll back only if that language is still selected and do not enqueue an API write. Do not call `saveLocale` directly when a context becomes unmounted; the queued coordinator is the only locale/preference writer. Do not add a second queue.

- [ ] **Step 4: Run provider and locale tests**

Run: `flutter test test/core/services/locale_service_test.dart test/features/user/presentation/providers/settings_provider_theme_test.dart`

Expected: PASS.

- [ ] **Step 5: Inspect the focused diff**

Run: `git diff -- lib/features/user/presentation/providers/settings_provider.dart test/features/user/presentation/providers/settings_provider_theme_test.dart`

### Task 3: Remove competing locale writers

**Files:**
- Modify: `lib/main.dart`
- Modify: `lib/core/l10n/app_localizations.dart`
- Modify: `lib/core/widgets/language_switcher_button.dart`
- Modify: `lib/features/auth/presentation/widgets/auth_wrapper.dart`
- Modify: `lib/features/user/presentation/pages/settings_page.dart`
- Modify: `lib/features/user/presentation/providers/settings_provider.dart`

- [ ] **Step 1: Search all locale writers**

Run: `rg -n "setLocale\(|updateAppLocale\(|syncLocale\(" lib --glob '*.dart'`

Expected: direct writer in `main.dart`, `LocaleService`, and helper extension.

- [ ] **Step 2: Delete rebuild-driven synchronization**

Remove `_lastSyncedLanguage` and the post-frame locale sync block from `_LexiLingoAppState`. Keep the user's unrelated route changes in `main.dart` intact.

- [ ] **Step 3: Synchronize the effective language during settings load**

Change `loadSettings` to accept its caller's `BuildContext`. After computing the effective language, initialize `_confirmedLanguage` from the server result and request the effective locale through `LocaleService`. Update both callers in `auth_wrapper.dart` and `settings_page.dart`. The settings-page reload guard keeps the second call a no-op. Add a widget test proving initial settings load applies the effective language through the coordinator.

- [ ] **Step 4: Route the helper through LocaleService or remove it if unused**

If `LocaleHelper.switchLocale` has no callers, delete only that method. Keep the language-code/read helpers. `LanguageSwitcherButton` already calls `SettingsProvider` post-auth and `LocaleService` pre-auth; update it only for the new boolean return type.

- [ ] **Step 5: Prove one writer remains**

Run: `rg -n "setLocale\(" lib --glob '*.dart'`

Expected: only `LocaleService` and documentation comments.

- [ ] **Step 6: Run focused tests and inspect overlapping diffs**

Run: `flutter test test/core/services/locale_service_test.dart test/features/user/presentation/providers/settings_provider_theme_test.dart`

Run: `git diff -- lib/main.dart lib/features/user/presentation/pages/settings_page.dart`

Expected: locale/flag changes coexist with, but do not remove or stage, the user's existing route and `AppBackButton` edits. Do not commit these full files during the task.

## Chunk 2: Fast deploy-owned assets

### Task 4: Use bundled translations and revalidation headers

**Files:**
- Modify: `lib/main.dart`
- Delete: `lib/core/localization/network_first_asset_loader.dart`
- Modify: `web/index.html`
- Modify: `vercel.json`
- Create: `test/web/vercel_cache_policy_test.dart`

- [ ] **Step 1: Add a cache-policy regression test**

Parse `vercel.json` with `dart:convert` and assert there is exactly one `Cache-Control` header declaration, on source `/(.*)`, with value `no-cache`. This single catch-all covers `/`, SPA rewrite responses, bootstrap/entrypoint, emitted manifests, `/canvaskit/**`, i18n, fonts, and flags without matcher-precedence assumptions.

- [ ] **Step 2: Verify the test fails**

Run: `flutter test test/web/vercel_cache_policy_test.dart`

Expected: FAIL on the current broad immutable matcher.

- [ ] **Step 3: Remove network-first translation loading**

Remove the `NetworkFirstAssetLoader` import and both `assetLoader` arguments in `main.dart`, then delete the unused loader file. EasyLocalization will use bundled JSON.

- [ ] **Step 4: Remove obsolete service-worker and CJK network-font HTML**

Delete the service-worker registration/cache-deletion script and the Google CJK stylesheet/preconnect tags from `web/index.html`. Keep existing metadata and layout CSS.

- [ ] **Step 5: Replace Vercel cache rules**

Delete all existing cache-specific header blocks. Add `Cache-Control: no-cache` to the existing `/(.*)` security-header block alongside COOP/COEP. This is intentionally one policy for every generated file; conditional `304` responses retain browser speed without stale stable-name assets.

- [ ] **Step 6: Run test and build**

Run: `flutter test test/web/vercel_cache_policy_test.dart`

Expected: PASS.

Run: `flutter build web --release`

Expected: build succeeds and `build/web/assets/assets/i18n/*.json` exists without requiring network translation code.

- [ ] **Step 7: Inspect generated paths**

Run: `find build/web -maxdepth 3 -type f | rg "(AssetManifest|FontManifest|canvaskit|\.wasm$|i18n)"`

Adjust only the Vercel matchers proven inaccurate by this output, then rerun the policy test.

- [ ] **Step 8: Inspect Web cache changes**

Run: `git diff -- web/index.html vercel.json lib/main.dart lib/core/localization/network_first_asset_loader.dart test/web/vercel_cache_policy_test.dart`

### Task 5: Bundle language flags

**Files:**
- Create: `assets/flags/vn.png`
- Create: `assets/flags/us.png`
- Create: `assets/flags/jp.png`
- Create: `assets/flags/kr.png`
- Create: `assets/flags/cn.png`
- Create: `assets/flags/fr.png`
- Create: `assets/flags/es.png`
- Modify: `pubspec.yaml`
- Modify: `lib/core/l10n/app_localizations.dart`
- Create: `lib/core/widgets/language_flag.dart`
- Modify: `lib/features/user/presentation/pages/settings_page.dart`
- Modify: `lib/core/widgets/language_switcher_button.dart`
- Modify: `lib/features/auth/presentation/pages/pre_auth_questions_page.dart`
- Delete: `lib/core/services/language_flag_cache.dart`
- Delete: `test/core/services/language_flag_cache_test.dart`
- Modify: `lib/main.dart`
- Create: `test/core/widgets/language_flag_asset_test.dart`

- [ ] **Step 1: Replace the old network-cache test with a flag-path/widget test**

Delete `test/core/services/language_flag_cache_test.dart`. Add the new asset test asserting every supported locale resolves to an existing declared asset. Create one public shared `LanguageFlag` widget and test that its `errorBuilder` fallback renders for an invalid asset.

- [ ] **Step 2: Acquire the seven small PNG flags**

Download once from the existing FlagCDN URLs, resize/compress to the largest rendered requirement, and store them under `assets/flags/`. This is a build-time operation only.

- [ ] **Step 3: Switch flag metadata and widgets to assets**

Add `flagAssetOf(code) => 'assets/flags/${flagCodeOf(code)}.png'`. Implement `LanguageFlag` in `lib/core/widgets/language_flag.dart` with `Image.asset(..., errorBuilder: ...)`, then replace all three language-only network flag implementations with it. This replaces duplication rather than adding a parallel widget. Preserve the unrelated `AppBackButton` change in `settings_page.dart`.

- [ ] **Step 4: Delete network preloading**

Remove `LanguageFlagCache.preload` from `main.dart`, delete the service, and remove imports that become unused.

- [ ] **Step 5: Test and inspect flags**

Run: `flutter test test/core/widgets/language_flag_asset_test.dart`

Expected: PASS.

Run: `git diff -- lib/main.dart lib/features/user/presentation/pages/settings_page.dart`

Expected: unrelated existing edits are preserved and remain unstaged.

### Task 6: Bundle CJK fallback fonts

**Files:**
- Create: `assets/fonts/NotoSansJP-VariableFont_wght.ttf`
- Create: `assets/fonts/NotoSansKR-VariableFont_wght.ttf`
- Create: `assets/fonts/NotoSansSC-VariableFont_wght.ttf`
- Create: `assets/fonts/OFL.txt`
- Modify: `pubspec.yaml`
- Modify: `lib/core/theme/app_theme.dart`
- Create: `test/core/theme/cjk_font_fallback_test.dart`

- [ ] **Step 1: Add a theme fallback test**

Assert every text style used by `AppTheme.lightTheme` and `darkTheme` has the three registered family names in `fontFamilyFallback`. Glyph rendering remains an explicit manual release-build check because Flutter widget tests cannot prove browser font rasterization.

- [ ] **Step 2: Acquire official variable font files**

Download the three OFL-licensed Google Noto variable fonts into `assets/fonts/` and store their OFL license as `assets/fonts/OFL.txt`.

- [ ] **Step 3: Register exact families**

Declare `NotoSansSC`, `NotoSansJP`, and `NotoSansKR` in `pubspec.yaml` and update `_withCjkFallback` to those exact names. Do not change global Lexend or admin Space Grotesk behavior.

- [ ] **Step 4: Verify fonts**

Run: `flutter test test/core/theme/cjk_font_fallback_test.dart`

Run: `flutter build web --release`

Expected: PASS; generated `FontManifest` includes all three families.

Manual command: `cd build/web && python3 -m http.server 8080`

Open `http://localhost:8080`, navigate to Settings, and verify the visible labels `中文`, `日本語`, and `한국어` contain no `□` in Chrome. Record this as manual verification; do not add a debug-only route.

- [ ] **Step 5: Inspect font changes**

Run: `git diff -- pubspec.yaml lib/core/theme/app_theme.dart test/core/theme/cjk_font_fallback_test.dart`

## Chunk 3: Final verification

### Task 7: Run the complete checks and reviews

**Files:**
- Modify only files required by test/review findings.

- [ ] **Step 1: Run formatting**

Run: `dart format lib/core/services/locale_service.dart lib/features/user/presentation/providers/settings_provider.dart lib/main.dart lib/core/l10n/app_localizations.dart lib/core/widgets/language_switcher_button.dart lib/core/widgets/language_flag.dart lib/features/auth/presentation/widgets/auth_wrapper.dart lib/features/user/presentation/pages/settings_page.dart lib/features/auth/presentation/pages/pre_auth_questions_page.dart test/core test/features/user/presentation/providers/settings_provider_theme_test.dart test/web`

- [ ] **Step 2: Run focused tests**

Run: `flutter test test/core/services/locale_service_test.dart test/features/user/presentation/providers/settings_provider_theme_test.dart test/core/widgets/language_flag_asset_test.dart test/core/theme/cjk_font_fallback_test.dart test/web/vercel_cache_policy_test.dart`

Expected: PASS.

- [ ] **Step 3: Run static analysis**

Run: `flutter analyze`

Expected: no new errors or warnings from touched files.

- [ ] **Step 4: Run production build**

Run: `flutter build web --release`

Expected: successful build.

- [ ] **Step 5: Delegate required regression review**

Spawn `test-writer` to inspect and add missing feature/bug-fix coverage without editing implementation files. Then spawn `code-reviewer` to review the complete diff. Apply only actionable findings and rerun the checks above.

- [ ] **Step 6: Verify deployed headers after deployment**

Run `curl -I` against the production URLs for `/`, `/flutter_bootstrap.js`, `/main.dart.js`, emitted manifests, one i18n JSON, one flag, and one font. Expected: stable-name resources revalidate and none returns a one-year immutable policy.

- [ ] **Step 7: Preserve worktree ownership**

Run: `git status --short` and `git diff --check`.

Do not commit or stage the implementation automatically: `main.dart` and `settings_page.dart` already contain unrelated user changes. Report the exact touched files so the user can stage the intended hunks safely.
