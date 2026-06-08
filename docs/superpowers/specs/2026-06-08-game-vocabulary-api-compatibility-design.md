# Game and Vocabulary API Compatibility Design

## Goal

Stop the production Flutter app from issuing unsupported API requests while
preserving the starter reward feature for environments where its backend route
has been deployed.

## Diagnosis

The vocabulary deck error is a request-contract mismatch. Production rejects
`GET /vocabulary/collection?limit=1000` because its deployed route accepts at
most 100 items. The current Flutter source already requests 100, but no
regression test protects that limit.

The starter reward error is a rollout-order mismatch. Flutter calls
`GET /gamification/rewards/starter/pending`, while the production backend
currently returns 404. The route and its backend tests exist in the repository,
so the client and server were not deployed as one compatible release.

## Design

### Starter Reward Rollout Gate

Add `ApiConfig.enableStarterReward`, sourced from
`ENABLE_STARTER_REWARD`. Development defaults to enabled so local integration
continues to exercise the feature. Production defaults to disabled, requiring
an explicit opt-in after the backend route and migration are live.

`GamificationProvider` receives the resolved flag and skips pending/seen
requests when disabled. Its constructor accepts an optional `ApiClient` and
flag override so provider behavior can be tested without the service locator.

The production Flutter build config explicitly sets
`ENABLE_STARTER_REWARD=false`. Deployment can change this to `true` only after
the production backend supports both starter reward endpoints.

### Vocabulary Collection Contract

Keep deck synchronization at a page size of 100, the maximum supported by both
old and current backends. Define the value as a named constant in
`VocabProvider` and add a provider test that asserts the exact outgoing query.

Add backend route tests proving `limit=100` is accepted and `limit=1001` is
rejected under the repository's current maximum of 1000. This protects the
current backend contract while Flutter intentionally uses the lower
cross-version-compatible value.

### Error Handling

When starter reward is disabled, the provider returns no pending reward and
does not send an HTTP request. Other gamification APIs remain unaffected.

Vocabulary backend failures remain non-blocking because the deck already keeps
locally stored words when synchronization fails.

## Verification

- Flutter provider test: disabled starter reward sends no request.
- Flutter provider test: enabled starter reward parses a successful response.
- Flutter deck provider test: collection request uses `limit=100`.
- Backend route tests: collection accepts 100 and rejects values above 1000.
- Run focused Flutter and backend tests.
- Run `dart format` and `flutter analyze`.

