# Flutter Page Access Map

Updated: 2026-04-14
Scope: `flutter-app/lib` navigation audit for pages/screens that are actually reachable.

## 1. App Entry Flow

Primary entry:
- App root: [flutter-app/lib/main.dart](flutter-app/lib/main.dart)
- `home` points to `AuthWrapper`: [flutter-app/lib/main.dart#L288](flutter-app/lib/main.dart#L288)

Auth wrapper flow:
- Wrapper file: [flutter-app/lib/features/auth/presentation/widgets/auth_wrapper.dart](flutter-app/lib/features/auth/presentation/widgets/auth_wrapper.dart)
- Unauthenticated:
  - `WelcomePage` (first-time local flag)
  - `LoginPage`
  - `RegisterPage`
- Authenticated:
  - `OnboardingPage` (if onboarding not completed)
  - `MainScreen` (normal logged-in path)

## 2. Main Navigable Hub (Bottom Navigation)

Bottom-tab host:
- [flutter-app/lib/features/home/presentation/pages/main_screen.dart](flutter-app/lib/features/home/presentation/pages/main_screen.dart)

Indexed pages (in order):
1. `HomePageNew` (Discovery)
2. `CourseListScreen` (Learning)
3. `LexiChatPage` (Lexi)
4. `StorySelectionPage` (Chat)
5. `ProfilePage` (Account)

Source list:
- [flutter-app/lib/features/home/presentation/pages/main_screen.dart#L47](flutter-app/lib/features/home/presentation/pages/main_screen.dart#L47)

## 3. Named Routes (MaterialApp routes)

Route table is declared in:
- [flutter-app/lib/main.dart#L289](flutter-app/lib/main.dart#L289)

Configured named routes:
- `/youtube` -> `YouTubeExploreScreen`
- `/youtube/player` -> `YouTubePlayerScreen`
- `/news` -> `NewsListScreen`
- `/news/detail` -> `NewsDetailScreen`
- `/news/quiz` -> `NewsQuizScreen`
- `/games` -> `GamesHubScreen`
- `/podcast` -> `PodcastExploreScreen`
- `/podcast/detail` -> `PodcastDetailScreen`
- `/podcast/player` -> `PodcastPlayerScreen`
- `/books` -> `BookLibraryScreen`
- `/lexi` -> `LexiChatPage`
- `/reset-password` -> `ResetPasswordPage`

## 4. Confirmed Reachable Feature Pages

The pages below are wired by tab navigation, named routes, or `Navigator.push(...)` from reachable screens.

### 4.1 Auth and Account
- `WelcomePage`, `LoginPage`, `RegisterPage`, `OnboardingPage` via `AuthWrapper`
- `ResetPasswordPage` via `/reset-password` route
- `EditProfileScreen` from `ProfilePage`
- `SettingsPage` from `ProfilePage`
- `VoicePracticeScreen` from `ProfilePage` app bar mic shortcut

### 4.2 Social and Gamification
- `SocialScreen` is reachable from `ProfilePage` quick action "Friends":
  - [flutter-app/lib/features/profile/presentation/pages/profile_page.dart#L256](flutter-app/lib/features/profile/presentation/pages/profile_page.dart#L256)
- `ShopScreen` from `ProfilePage`
- `LeaderboardScreen` from `ProfilePage`
- `WalletScreen` from `ProfilePage` and `HomePageNew`
- `AchievementsScreen` from `ProfilePage`
- `MyProgressScreen` from `ProfilePage` quick action `Progress`

### 4.3 Learning and Chat
- `CourseListScreen` via bottom tab
- `CategoryDetailScreen` from `CourseListScreen`
- `CourseDetailScreen` from `CourseListScreen` and `HomePageNew`
- `LearningRoadmapScreen` from `CourseDetailScreen`
- `LearningSessionScreen` from `LearningRoadmapScreen`
- `StorySelectionPage` via bottom tab
- `TopicChatPage` from `StorySelectionPage`
- `LexiChatPage` via bottom tab and `/lexi`

### 4.4 Content Modules
- News flow: `NewsListScreen` -> `NewsDetailScreen` -> `NewsQuizScreen`
- Games flow: `GamesHubScreen` -> individual game screens -> `GameResultScreen`
- Podcast flow: `PodcastExploreScreen` -> `PodcastDetailScreen` -> `PodcastPlayerScreen`
- Books flow: `BookLibraryScreen` -> `BookDetailScreen`
- Vocabulary flow: `FlashcardReviewScreen` -> `SessionCompleteScreen`

## 5. Current Potentially Unreachable Pages

No known unreachable pages are tracked in the current audited set.
Recent cleanup/actions:
- Removed `PlacementTestScreen` because it was not wired.
- Wired `MyProgressScreen` from `ProfilePage` quick actions.
- Wired `VoicePracticeScreen` from `ProfilePage` app bar shortcut.

Note:
- "Potentially unreachable" means not currently wired in app navigation paths. It may still be intended for future work.

## 6. Quick Manual Verification Checklist

Run app and verify:
1. Login -> lands in `MainScreen`.
2. Open Account tab -> tap Friends -> opens `SocialScreen`.
3. From Discovery, open at least one deep page (e.g., Wallet or Course detail).
4. Open each named route feature from its corresponding UI entry:
   - News, Games, Podcast, Books.
5. Verify `Progress` quick action opens `MyProgressScreen`.
6. Verify app bar mic shortcut opens `VoicePracticeScreen`.

## 7. Maintenance Rules

When adding a new page/screen:
1. Add route wiring (tab, named route, or push from reachable page).
2. Add one line in this document under section 4.
3. If page is temporary/experimental, record it under section 5 with reason.
