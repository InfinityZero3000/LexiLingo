import 'package:lexilingo_app/features/auth/data/datasources/token_storage.dart';
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/account_data_cleaner.dart';
import 'package:lexilingo_app/core/services/known_words_service.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:lexilingo_app/core/services/podcast_audio_handler.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/podcast/data/services/listening_history_recorder.dart';
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/speech_recognition_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';

enum SessionChange { none, signedIn, signedOut, accountSwitched }

/// Turns the auth state of each build into what the session sync owes. An
/// account switch is its own case: it can arrive with no signed-out frame in
/// between, and the previous learner's data must still go first.
class SessionTracker {
  String? _userId;
  bool _active = false;

  SessionChange update({required bool authenticated, String? userId}) {
    if (!authenticated) {
      if (!_active) return SessionChange.none;
      _active = false;
      _userId = null;
      return SessionChange.signedOut;
    }
    if (!_active) {
      _active = true;
      _userId = userId;
      return SessionChange.signedIn;
    }
    if (_userId == null) {
      _userId = userId;
      return SessionChange.none;
    }
    if (userId != null && userId != _userId) {
      _userId = userId;
      return SessionChange.accountSwitched;
    }
    return SessionChange.none;
  }
}

/// Keeps per-user state tied to the signed-in user. Providers outlive a
/// session, so without this a sign-out left the last learner's numbers in
/// memory and a sign-in showed them until something happened to reload.
///
/// Every root provider that holds learner data is reset here, or is named in
/// the allowlist of `user_session_sync_guard_test.dart` with the reason it
/// does not need to be. A provider without a reset is how one learner's gems,
/// chats and words ended up on the next learner's screen.
abstract final class UserSessionSync {
  static final Set<Type> _unbuilt = <Type>{};
  static final Set<Type> _built = <Type>{};

  @visibleForTesting
  static void debugResetBuildTracking() {
    _unbuilt.clear();
    _built.clear();
  }

  /// A root provider that remembers whether anything has built it yet. Providers
  /// stay lazy, and sign-out must not construct one just to reset it: building
  /// runs its loads, with no session to load for.
  static ChangeNotifierProvider<T> provider<T extends ChangeNotifier>(
    T Function() create,
  ) {
    if (!_built.contains(T)) _unbuilt.add(T);
    return ChangeNotifierProvider<T>(
      create: (_) {
        final built = create();
        _unbuilt.remove(T);
        _built.add(T);
        return built;
      },
    );
  }

  /// First thing every sign-in does. Another account taking over has no
  /// signed-out frame, so it goes through exactly the sign-out path: every
  /// provider is reset at once (before this returns its future). Whatever the
  /// path, the previous learner's caches are cleared unless they are already
  /// this learner's; the new learner's loads wait for that future.
  static Future<void> beforeSignIn(
    BuildContext context,
    SessionChange change, {
    String? userId,
  }) async {
    LocalCacheService.instance.clearUserMemory();
    if (change == SessionChange.accountSwitched) {
      afterSignOut(context);
      // Start the stored half now: reads queue behind it on the database.
      unawaited(
        LocalCacheService.instance.clearUserEntries().catchError((Object _) {}),
      );
    }
    await AccountDataCleaner.clearForSignIn(userId);
  }

  /// Runs while the learner's token is still valid, before a deliberate
  /// sign-out: flashcard ratings already on their way get a moment to arrive
  /// instead of being dropped at reset. A session that expired cannot do this;
  /// its ratings are dropped, and their words simply come due again.
  static Future<void> beforeSignOut(BuildContext context) async {
    if (_unbuilt.contains(FlashcardProvider)) return;
    await _maybe<FlashcardProvider>(context)?.flushDelivery();
  }

  /// The signed-out transition seen by the app shell: reset everything in
  /// memory at once, then clear the caches. The clean-up is repeated here even
  /// though sign-out already ran it, because a session can end without one.
  static Future<void> onSignedOut(BuildContext context) async {
    afterSignOut(context);
    // In a browser tab left behind by another account's sign-in, those caches
    // are theirs now.
    if (sl.isRegistered<TokenStorage>() &&
        await sl<TokenStorage>().heldByAnotherAccount()) {
      return;
    }
    await AccountDataCleaner.clear();
  }

  static void afterSignOut(BuildContext context) {
    // Synchronous and first: nothing may await before the learner's cached
    // XP and proficiency are gone from memory.
    LocalCacheService.instance.clearUserMemory();
    _resetServices();
    _reset<UserProvider>(context, (p) => p.reset());
    _reset<HomeProvider>(context, (p) => p.clear());
    _reset<ProfileProvider>(context, (p) => p.clear());
    _reset<ChatProvider>(context, (p) => p.reset());
    _reset<StoryProvider>(context, (p) => p.reset());
    _reset<CourseProvider>(context, (p) => p.reset());
    _reset<LearningProvider>(context, (p) => p.reset());
    _reset<ProgressProvider>(context, (p) => p.reset());
    _reset<VocabProvider>(context, (p) => p.reset());
    _reset<FlashcardProvider>(context, (p) => p.reset());
    _reset<VoiceProvider>(context, (p) => p.clearResults());
    _reset<SpeechRecognitionProvider>(context, (p) => p.reset());
    _reset<StreakProvider>(context, (p) => p.reset());
    _reset<DailyChallengesProvider>(context, (p) => p.reset());
    _reset<ContentActivityProvider>(context, (p) => p.reset());
    _reset<AchievementProvider>(context, (p) => p.reset());
    _reset<NotificationProvider>(context, (p) => p.reset());
    _reset<LevelProvider>(context, (p) => p.reset());
    _reset<ProficiencyProvider>(context, (p) => p.reset());
    _reset<GamificationProvider>(context, (p) => p.reset());
    _reset<SocialProvider>(context, (p) => p.reset());
    _reset<YouTubeProvider>(context, (p) => p.reset());
    _reset<NewsProvider>(context, (p) => p.reset());
    _reset<GamesProvider>(context, (p) => p.reset());
    _reset<PodcastProvider>(context, (p) => p.reset());
    _reset<BookProvider>(context, (p) => p.reset());
    _reset<LexiChatProvider>(context, (p) => p.reset());
  }

  /// Singletons outside the widget tree that hold learner data in memory.
  static void _resetServices() {
    if (sl.isRegistered<KnownWordsService>()) sl<KnownWordsService>().reset();
    if (sl.isRegistered<ListeningHistoryRecorder>()) {
      sl<ListeningHistoryRecorder>().reset();
    }
    if (sl.isRegistered<PodcastAudioHandler>()) {
      unawaited(sl<PodcastAudioHandler>().stop().catchError((_) {}));
    }
  }

  static void _reset<T>(BuildContext context, void Function(T) reset) {
    if (_unbuilt.contains(T)) return;
    final provider = _maybe<T>(context);
    if (provider != null) reset(provider);
  }

  static Future<void> afterSignIn(BuildContext context) async {
    final streak = _maybe<StreakProvider>(context);
    final level = _maybe<LevelProvider>(context);
    final home = _maybe<HomeProvider>(context);
    final challenges = _maybe<DailyChallengesProvider>(context);
    final vocab = _maybe<VocabProvider>(context);
    final games = _maybe<GamesProvider>(context);
    final story = _maybe<StoryProvider>(context);
    final notifications = _maybe<NotificationProvider>(context);
    await Future.wait([
      if (streak != null) streak.loadStreak(maxAge: kPassiveReloadWindow),
      if (level != null) level.fetchLevelFull(maxAge: kPassiveReloadWindow),
      if (home != null) home.loadWeeklyProgress(maxAge: kPassiveReloadWindow),
      if (challenges != null) challenges.loadChallenges(),
      if (vocab != null) ...[vocab.loadWords(), vocab.loadDecks()],
      if (games != null && !kIsWeb) games.loadXPProfile(),
      if (story != null) story.loadRecentlyUsed(),
      if (notifications != null) notifications.loadNotifications(),
    ]);
  }

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
