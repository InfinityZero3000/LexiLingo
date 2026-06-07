# New User Starter Gem Reward Design

## Goal

Give every newly created learner account 100 Gems exactly once, record the
reward against the first creation of its backend user ID, and present the
reward only after the learner reaches the main application interface.

The feature applies to new email/password, Google, and Facebook accounts
created after deployment. Existing accounts are not backfilled.

## Current State

The backend creates email/password users in the registration route and creates
social-login users through Firebase account mapping. These paths currently do
not share a post-creation reward hook.

Wallets are created lazily with a zero balance. `WalletCRUD.add_gems` records
earn transactions, but its current wallet creation path commits internally,
which prevents user creation, reward grant, wallet transaction, and in-app
notification from being committed atomically.

The Flutter app already has wallet state, notifications, FCM device
registration, and full-screen celebration patterns. It does not have a
dedicated starter-reward popup or a server-authoritative "shown" state.

## Architecture

### Starter Reward Grant

Add a `user_reward_grants` table that represents idempotent, one-time rewards.
Each row contains:

- `id`
- `user_id`
- `reward_key`
- `gems_awarded`
- `created_at`
- `popup_seen_at`
- `push_sent_at`

The database enforces a unique constraint on `(user_id, reward_key)`.
The starter reward uses the stable key `new_user_starter_gems_v1` and an amount
of 100 Gems.

This table is the source of truth for whether the reward was granted, whether
the main-screen popup still needs to be shown, and whether a push has already
been attempted successfully. Local preferences must not decide eligibility.

### Starter Reward Service

Add a focused `StarterRewardService.grant_new_user_reward` operation. It
receives an already-created `user_id` and the active database session, then:

1. Creates the unique reward-grant row.
2. Creates or loads the user's wallet without committing independently.
3. Adds 100 Gems and increments total Gems earned.
4. Creates a wallet transaction with source `new_user_starter_reward`.
5. Creates an unread in-app notification with type `starter_reward` and data
   containing the reward key and Gem amount.
6. Flushes changes without owning the outer commit.

The caller commits user creation and all reward records together. A unique-key
conflict is treated as "already granted" and must not add Gems again.

Wallet creation and Gem addition helpers will support caller-managed
transactions. Existing callers that rely on their current commit behavior
remain compatible.

### User Creation Integration

Every backend path that creates a new learner user invokes the service only
inside its actual creation branch:

- Email/password registration.
- First Google account mapping.
- First Facebook account mapping.

Finding an existing user by email, linking another authentication provider, or
logging in again does not invoke the grant. Admin and super-admin accounts are
not eligible even when created through an authentication path; eligibility is
limited to the normal learner role.

The shared Firebase account-mapping helper must return whether it created a
user, or encapsulate the reward call inside the new-user branch. Provider
linking must never be mistaken for account creation.

### Reward Status API

Add authenticated endpoints under gamification:

- `GET /gamification/rewards/starter/pending`
- `POST /gamification/rewards/starter/seen`

The pending endpoint returns either no pending reward or a payload containing:

- reward key
- Gem amount
- current wallet balance
- in-app notification title and body

The seen endpoint sets `popup_seen_at` idempotently. It does not modify the
wallet balance and succeeds when called more than once.

Only the authenticated owner can read or acknowledge the grant.

### Push Delivery

The durable in-app notification is created at grant time even when the backend
does not yet know an FCM token.

After a device token is registered or refreshed, the backend checks for an
unsent starter-reward notification for that user. If found, it sends an FCM
notification with:

- type `starter_reward`
- reward key
- Gem amount
- route targeting the main application interface

When Firebase confirms at least one successful delivery,
`push_sent_at` is recorded. Missing tokens, unavailable Firebase credentials,
or failed delivery leave `push_sent_at` empty so a later device registration
can retry. Failures do not roll back account creation or the Gem grant.

Flutter's existing foreground message handler must not render this as a system
banner or starter popup while the learner is using pre-main flows. Android and
iOS display the notification payload normally when the application is
backgrounded or terminated. Web retains the durable in-app notification even
if platform push is unavailable.

### Main-Screen Presentation

The Flutter app checks starter-reward status only after `MainScreen` is active.
Registration, email verification, login, pre-auth questions, and onboarding
must not invoke or display the popup.

The main-screen coordinator performs this sequence once per activation:

1. Request the pending starter reward.
2. If none exists, do nothing.
3. Refresh wallet state so counters show the authoritative 100-Gem balance.
4. Show the B-style centered modal.
5. When the learner closes the modal, acknowledge the reward on the backend.
6. Show the C-style confirmation card as a temporary in-app banner stating
   that 100 Gems were added to the wallet.

The B-style modal contains a Gem illustration, "Quà chào mừng", `100 GEM`, a
short shop-use explanation, and a primary "Tuyệt vời!" action. It is
non-dismissible until the action is pressed, preventing an accidental
barrier tap from losing the reward explanation.

The C-style banner is informational and does not require another server
mutation. It may be dismissed or expire automatically. It is not a second
reward and does not appear independently on later sessions.

If acknowledgement fails, the wallet remains correct and the grant remains
pending. The app may show the modal again on a later main-screen entry rather
than incorrectly marking it as seen locally.

### Localization and Accessibility

All new user-facing strings are added to the existing localization resources,
including Vietnamese and English.

The modal and banner use semantic theme colors, support light and dark modes,
scale within narrow mobile screens and Flutter Web, provide accessible labels
for the Gem illustration, and respect reduced-motion settings. Animation is
decorative and cannot delay acknowledgement.

## Error Handling

- Reward duplication is prevented by the database unique constraint.
- A registration retry that resolves to an existing user does not grant again.
- Reward creation failure rolls back new learner creation so the system cannot
  persist a new eligible user without its promised starter balance.
- Email delivery failure remains non-blocking after the account and reward
  transaction commits.
- Push failure is non-blocking and retryable from later device registration.
- Pending-status network failure leaves the learner on the main screen without
  a false success message; a later activation retries.
- Seen acknowledgement is idempotent and never changes Gem totals.

## Scope

Included:

- Backend schema and migration for reward grants.
- Atomic, idempotent 100-Gem grant for all new learner account providers.
- Wallet transaction and durable notification records.
- Pending and seen reward API.
- Background/terminated FCM delivery after token availability.
- B-style main-screen modal and C-style confirmation banner.
- English and Vietnamese localization.

Excluded:

- Backfilling existing accounts.
- Configurable reward campaigns or an admin campaign editor.
- Multiple starter reward tiers.
- Showing reward UI before the main interface.
- Treating push delivery as proof that the popup was seen.

## Verification

Backend tests cover:

- A new email account receives exactly 100 Gems.
- New Google and Facebook accounts receive the same reward.
- Existing-user login and provider linking do not grant Gems.
- Non-learner accounts are not granted the learner reward.
- Concurrent or repeated grant attempts create one grant and one wallet
  transaction.
- A failed reward transaction rolls back eligible user creation.
- Pending and seen endpoints enforce ownership and idempotency.
- Device registration sends an unsent push once and preserves retry state on
  failure.

Flutter tests cover:

- No popup on registration, verification, login, or onboarding surfaces.
- Pending reward triggers the B modal only after `MainScreen` is active.
- Closing B acknowledges the grant and displays C.
- Wallet state refreshes from the backend.
- Failed acknowledgement allows a later retry.
- Foreground FCM receipt does not bypass the main-screen coordinator.
- Light/dark, narrow-screen, and localized rendering remain valid.

Run focused backend tests, focused Flutter widget/provider tests, Dart
formatting, `flutter analyze` on touched files, and the relevant migration
upgrade/downgrade check.
