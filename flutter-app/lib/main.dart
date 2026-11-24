import 'dart:async';

import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, debugPrint;
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart' show AppLocales;
import 'package:lexilingo_app/core/l10n/cached_translation_loader.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lexilingo_app/core/widgets/locale_refresher.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lexilingo_app/firebase_options.dart';
import 'package:lexilingo_app/core/services/deep_link_service.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';
import 'package:lexilingo_app/core/services/firebase_messaging_service.dart';
import 'package:lexilingo_app/core/services/app_navigation_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/navigation/deferred_page.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
// import 'package:lexilingo_app/core/services/course_import_service.dart'; // Already disabled
import 'package:lexilingo_app/core/services/health_check_service.dart';
import 'package:lexilingo_app/core/startup/startup_coordinator.dart';
import 'package:lexilingo_app/core/startup/startup_task.dart';
import 'package:lexilingo_app/core/startup/local_state_migration_service.dart';
import 'package:lexilingo_app/core/services/sync_queue_lifecycle_runner.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/achievements/presentation/screens/achievements_screen.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/user_session_sync.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/reset_password_page.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/verify_email_page.dart';
import 'package:lexilingo_app/core/navigation/token_routes.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/auth_wrapper.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/level/presentation/pages/placement_test_page.dart'
    deferred as placement;
import 'package:lexilingo_app/features/level/presentation/pages/level_exam_page.dart'
    deferred as level_exam;
import 'package:lexilingo_app/features/level/presentation/providers/level_exam_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/placement_test_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/flashcard_review_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/word_of_day_screen.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/promo_banner_provider.dart';
import 'package:lexilingo_app/features/home/presentation/pages/today_plan_page.dart'
    deferred as today_plan;
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/speech_recognition_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/content_activity_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/social/presentation/screens/social_screen.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_explore_screen.dart'
    deferred as yt_explore;
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_player_screen.dart'
    deferred as yt_player;
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';
import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:lexilingo_app/features/news/presentation/screens/news_list_screen.dart'
    deferred as news_list;
import 'package:lexilingo_app/features/news/presentation/screens/news_detail_screen.dart'
    deferred as news_detail;
import 'package:lexilingo_app/features/news/presentation/screens/news_quiz_screen.dart'
    deferred as news_quiz;
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/games_hub_screen.dart'
    deferred as games_hub;
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_explore_screen.dart'
    deferred as pod_explore;
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_detail_screen.dart'
    deferred as pod_detail;
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_player_screen.dart'
    deferred as pod_player;
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_library_screen.dart'
    deferred as book_library;
import 'package:lexilingo_app/features/mistakes/presentation/pages/mistake_notebook_page.dart'
    deferred as mistakes;
import 'package:lexilingo_app/features/offline/presentation/pages/offline_sync_center_page.dart'
    deferred as offline_sync;
import 'package:lexilingo_app/features/premium/presentation/screens/paywall_screen.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';

String? _lastFlutterError;
bool _announcedRepeat = false;

// A throw inside MouseTracker leaves `_debugDuringDeviceUpdate` stuck, so every
// later pointer event re-asserts; print the first and swallow the identical rest.
void _onFlutterError(FlutterErrorDetails details) {
  final key = details.exceptionAsString();
  if (key == _lastFlutterError) {
    if (!_announcedRepeat) {
      _announcedRepeat = true;
      debugPrint(
        'Flutter Error repeating; duplicates suppressed. The first occurrence '
        'above is the root cause — hot restart to clear a stuck assertion.',
      );
    }
    return;
  }
  _lastFlutterError = key;
  _announcedRepeat = false;
  FlutterError.presentError(details);
  debugPrint('Flutter Error: ${details.exception}');
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();

  if (kIsWeb) {
    // Avoid sqflite web worker boot failures when sqflite_sw.js is not deployed.
    databaseFactory = databaseFactoryFfiWebNoWebWorker;
  }

  // Add error handler for Flutter and Dart errors
  FlutterError.onError = _onFlutterError;

  try {
    // Load only public client config. Raw .env files may contain server
    // secrets and must never be bundled into Flutter web assets.
    final envFile = kReleaseMode
        ? 'assets/env/prod_config'
        : 'assets/env/dev_config';
    await dotenv.load(fileName: envFile);
  } catch (e) {
    debugPrint('Warning: Could not load public config: $e');
  }

  debugPrint('Backend API base URL: ${ApiConfig.baseUrl}');
  debugPrint('AI service base URL: ${ApiConfig.aiServiceUrl}');

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');

    // Crashlytics: route Flutter framework errors to Crashlytics in release
    if (!kIsWeb) {
      FlutterError.onError = kReleaseMode
          ? FirebaseCrashlytics.instance.recordFlutterFatalError
          : _onFlutterError;
      // Also catch async errors thrown outside the Flutter widget tree
    }

    // Initialize Firebase Cloud Messaging
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Push notification permission should not block app startup
    // so we delay it until after runApp()
  } catch (e) {
    debugPrint('Warning: Firebase initialization failed: $e');
  }

  // Initialize Dependency Injection (skip database on web)
  await LocalStateMigrationService().runIfNeeded();
  await di.initializeDependencies(skipDatabase: kIsWeb);

  // Initialize local notifications early so Settings sync can schedule reliably.
  await di.sl<NotificationService>().ensureInitialized();

  // Run startup tasks (health check, seeding). Keep non-blocking for first frame.
  if (!kIsWeb) {
    final coordinator = StartupCoordinator(
      tasks: [
        StartupTask(
          id: 'health_check',
          label: 'Ping backend /health',
          action: () async {
            final ok = await di.sl<HealthCheckService>().ping();
            if (!ok) throw Exception('Backend health check failed');
          },
        ),
      ],
    );

    unawaited(
      coordinator.run(
        onProgress: (result) => logDebug(
          'Startup',
          '${result.id}: ${result.status.name} ${result.message ?? ''}',
        ),
      ),
    );
  }

  // Wrap runApp in runZonedGuarded so uncaught async errors are forwarded to
  // Crashlytics. In release mode only — dev keeps the default red-screen behavior.
  if (!kIsWeb && kReleaseMode) {
    runZonedGuarded(
      () => runApp(_localizedApp()),
      (error, stack) =>
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true),
    );
  } else {
    runApp(_localizedApp());
  }

  // Initialize Firebase Messaging and Deep Links after UI starts rendering
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await FirebaseMessagingService.instance.initialize();
      debugPrint('Firebase Messaging initialized successfully');
    } catch (e) {
      debugPrint('Warning: Firebase Messaging initialization failed: $e');
    }
    try {
      await DeepLinkService.instance.init();
      debugPrint('Deep link service initialized');
    } catch (e) {
      debugPrint('Warning: Deep link service initialization failed: $e');
    }
    if (!kIsWeb) {
      try {
        await PurchasesService.instance.init(
          iosApiKey: dotenv.maybeGet('REVENUECAT_API_KEY_IOS'),
          androidApiKey: dotenv.maybeGet('REVENUECAT_API_KEY_ANDROID'),
        );
      } catch (e) {
        debugPrint('Warning: RevenueCat initialization failed: $e');
      }
    }
  });
}

const _translationsPath = CachedTranslationLoader.translationsPath;

Widget _localizedApp() => EasyLocalization(
  supportedLocales: AppLocales.supportedLocales,
  path: _translationsPath,
  assetLoader: const CachedTranslationLoader(),
  fallbackLocale: const Locale('vi'),
  startLocale: const Locale('vi'),
  useOnlyLangCode: true,
  child: const LexiLingoApp(),
);

class LexiLingoApp extends StatefulWidget {
  const LexiLingoApp({super.key});

  @override
  State<LexiLingoApp> createState() => _LexiLingoAppState();
}

class _LexiLingoAppState extends State<LexiLingoApp>
    with WidgetsBindingObserver {
  SyncQueueLifecycleRunner? _syncQueueRunner;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (!kIsWeb) {
      _syncQueueRunner = SyncQueueLifecycleRunner(
        apiClient: di.sl<ApiClient>(),
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncQueueRunner?.start();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncQueueRunner?.stop();
    DeepLinkService.instance.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncQueueRunner?.onAppResumed();
    }
  }

  String? _extractResetTokenFromDeepLink() {
    final pending = DeepLinkService.instance.pendingResetToken;
    if (pending != null && pending.isNotEmpty) {
      DeepLinkService.instance.pendingResetToken = null;
      return pending;
    }
    return _tokenFromPageUrl();
  }

  String? _extractVerifyTokenFromDeepLink() {
    final pending = DeepLinkService.instance.pendingVerifyToken;
    if (pending != null && pending.isNotEmpty) {
      DeepLinkService.instance.pendingVerifyToken = null;
      return pending;
    }
    return _tokenFromPageUrl();
  }

  // Flutter web uses hash URLs, so a mailed link like /verify-email?token=… opens "/" and the
  // token is only in the page URL (query or fragment).
  String? _tokenFromPageUrl() {
    final queryToken = Uri.base.queryParameters['token'];
    if (queryToken != null && queryToken.isNotEmpty) {
      return queryToken;
    }

    final fragment = Uri.base.fragment;
    if (fragment.isNotEmpty) {
      final fragmentUri = Uri.tryParse(fragment);
      final fragmentToken = fragmentUri?.queryParameters['token'];
      if (fragmentToken != null && fragmentToken.isNotEmpty) {
        return fragmentToken;
      }
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => di.sl<AuthProvider>()),
        UserSessionSync.provider(() => di.sl<UserProvider>()),
        UserSessionSync.provider(() => di.sl<HomeProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<PromoBannerProvider>()),
        UserSessionSync.provider(() => di.sl<ProfileProvider>()),
        UserSessionSync.provider(() => di.sl<ChatProvider>()),
        UserSessionSync.provider(() => di.sl<StoryProvider>()),
        UserSessionSync.provider(() => di.sl<CourseProvider>()),
        UserSessionSync.provider(() => di.sl<LearningProvider>()),
        UserSessionSync.provider(() => di.sl<ProgressProvider>()),
        UserSessionSync.provider(() => di.sl<VocabProvider>()),
        UserSessionSync.provider(() => di.sl<FlashcardProvider>()),
        UserSessionSync.provider(() => di.sl<VoiceProvider>()),
        UserSessionSync.provider(() => di.sl<SpeechRecognitionProvider>()),
        ChangeNotifierProvider(
          create: (_) => di.sl<TtsSettingsProvider>()..init(),
        ),
        // Loaded by UserSessionSync once someone is signed in; an eager load
        // here ran with no token and 401'd on every cold start.
        UserSessionSync.provider(() => di.sl<StreakProvider>()),
        UserSessionSync.provider(() => di.sl<DailyChallengesProvider>()),
        // No eager load: the Content tab calls load() when first opened.
        UserSessionSync.provider(() => di.sl<ContentActivityProvider>()),
        UserSessionSync.provider(() => di.sl<AchievementProvider>()),
        UserSessionSync.provider(() => di.sl<NotificationProvider>()),
        UserSessionSync.provider(() => di.sl<LevelProvider>()),
        UserSessionSync.provider(() => di.sl<ProficiencyProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<SettingsProvider>()),
        UserSessionSync.provider(() => di.sl<GamificationProvider>()),
        UserSessionSync.provider(() => di.sl<SocialProvider>()),
        // Phase 1: YouTube Video Integration
        UserSessionSync.provider(() => di.sl<YouTubeProvider>()),
        // Phase 2: News Reading
        UserSessionSync.provider(() => di.sl<NewsProvider>()),
        // Phase 3: English Games + XP System
        // The XP profile loads from UserSessionSync once someone is signed in.
        UserSessionSync.provider(() => di.sl<GamesProvider>()),
        // Phase 4: Podcast
        // On web: defer curated podcast load (AudioService not available on web)
        UserSessionSync.provider(() {
          final p = di.sl<PodcastProvider>();
          if (!kIsWeb) p.loadCuratedPodcasts();
          return p;
        }),
        // Phase 5: Book Reading
        UserSessionSync.provider(() => di.sl<BookProvider>()),
        // Phase 6: Lexi Chat — Story Adventure
        UserSessionSync.provider(() => di.sl<LexiChatProvider>()),
      ],
      child: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          final routes = <String, WidgetBuilder>{
            '/youtube': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: yt_explore.loadLibrary,
                builder: (_) => yt_explore.YouTubeExploreScreen(),
              ),
            ),
            '/youtube/player': LearnerRoute.builder((context) {
              final video =
                  ModalRoute.of(context)!.settings.arguments as YouTubeVideo;
              return DeferredPage(
                loadLibrary: yt_player.loadLibrary,
                builder: (_) => yt_player.YouTubePlayerScreen(video: video),
              );
            }),
            '/news': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: news_list.loadLibrary,
                builder: (_) => news_list.NewsListScreen(),
              ),
            ),
            '/news/detail': LearnerRoute.builder((context) {
              final article =
                  ModalRoute.of(context)!.settings.arguments as NewsArticle;
              return DeferredPage(
                loadLibrary: news_detail.loadLibrary,
                builder: (_) => news_detail.NewsDetailScreen(article: article),
              );
            }),
            '/news/quiz': LearnerRoute.builder((context) {
              final article =
                  ModalRoute.of(context)!.settings.arguments as NewsArticle;
              return DeferredPage(
                loadLibrary: news_quiz.loadLibrary,
                builder: (_) => news_quiz.NewsQuizScreen(article: article),
              );
            }),
            // Phase 3: English Games
            '/games': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: games_hub.loadLibrary,
                builder: (_) => games_hub.GamesHubScreen(),
              ),
            ),
            '/courses': LearnerRoute.builder(
              (context) => const MainScreen(initialIndex: 1),
            ),
            '/today-plan': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: today_plan.loadLibrary,
                builder: (_) => today_plan.TodayPlanPage(),
              ),
            ),
            '/practice-lab': LearnerRoute.builder(
              (context) => const MainScreen(initialIndex: 3),
            ),
            '/mistake-notebook': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: mistakes.loadLibrary,
                builder: (_) => mistakes.MistakeNotebookPage(),
              ),
            ),
            '/profile': LearnerRoute.builder(
              (context) => const MainScreen(initialIndex: 4),
            ),
            '/achievements': LearnerRoute.builder(
              (context) => const AchievementsScreen(),
            ),
            '/social': LearnerRoute.builder((context) => const SocialScreen()),
            '/premium': LearnerRoute.builder(
              (context) => const PaywallScreen(),
            ),
            '/offline-sync': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: offline_sync.loadLibrary,
                builder: (_) => offline_sync.OfflineSyncCenterPage(),
              ),
            ),
            '/placement-test': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: placement.loadLibrary,
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => di.sl<PlacementTestProvider>(),
                  child: placement.PlacementTestPage(),
                ),
              ),
            ),
            '/level-exam': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: level_exam.loadLibrary,
                builder: (_) => ChangeNotifierProvider(
                  create: (_) => di.sl<LevelExamProvider>(),
                  child: level_exam.LevelExamPage(),
                ),
              ),
            ),
            '/vocabulary/review': LearnerRoute.builder(
              (context) => ChangeNotifierProvider(
                create: (_) => vocab_di.getIt<FlashcardProvider>(),
                child: const FlashcardReviewScreen(),
              ),
            ),
            '/vocabulary/word-of-day': LearnerRoute.builder(
              (context) => const WordOfDayScreen(),
            ),
            // Phase 4: Podcast
            '/podcast': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: pod_explore.loadLibrary,
                builder: (_) => pod_explore.PodcastExploreScreen(),
              ),
            ),
            '/podcast/detail': LearnerRoute.builder((context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args is! Podcast) return const _MissingRouteArgs();
              return DeferredPage(
                loadLibrary: pod_detail.loadLibrary,
                builder: (_) => pod_detail.PodcastDetailScreen(podcast: args),
              );
            }),
            '/podcast/player': LearnerRoute.builder((context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              if (args is! Map<String, dynamic> ||
                  args['episode'] is! PodcastEpisode ||
                  args['artworkUrl'] is! String) {
                return const _MissingRouteArgs();
              }
              return DeferredPage(
                loadLibrary: pod_player.loadLibrary,
                builder: (_) => pod_player.PodcastPlayerScreen(
                  episode: args['episode'] as PodcastEpisode,
                  artworkUrl: args['artworkUrl'] as String,
                ),
              );
            }),
            // Phase 5: Books
            '/books': LearnerRoute.builder(
              (context) => DeferredPage(
                loadLibrary: book_library.loadLibrary,
                builder: (_) => book_library.BookLibraryScreen(),
              ),
            ),
            // Phase 6: Lexi Chat
            '/lexi': LearnerRoute.builder((context) => const LexiChatPage()),
            '/reset-password': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              String? token;
              if (args is String) {
                token = args;
              } else if (args is Map<String, dynamic>) {
                token = args['token'] as String?;
              }
              token ??= _extractResetTokenFromDeepLink();
              return ResetPasswordPage(initialToken: token);
            },
            '/verify-email': (context) {
              final args = ModalRoute.of(context)?.settings.arguments;
              String? token;
              if (args is String) {
                token = args;
              } else if (args is Map<String, dynamic>) {
                token = args['token'] as String?;
              }
              token ??= _extractVerifyTokenFromDeepLink();
              return VerifyEmailPage(token: token);
            },
          };
          return MaterialApp(
            title: 'LexiLingo',
            navigatorKey: AppNavigationService.navigatorKey,
            navigatorObservers: [AppNavigationService.routeObserver],
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.themeMode,
            themeAnimationDuration: Duration.zero,
            builder: (context, child) {
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: AppTheme.systemUiOverlayStyle(
                  Theme.of(context).brightness,
                ),
                child: _TouchTargets(
                  child: LocaleRefresher(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              );
            },
            // Localization — easy_localization handles locale state
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const AuthWrapper(),
            routes: routes,
            onGenerateRoute: (settings) => queryRoute(settings, routes),
          );
        },
      ),
    );
  }
}

/// Shown when a named route is pushed without the arguments its screen
/// requires, instead of crashing on an unchecked `as` cast.
class _MissingRouteArgs extends StatelessWidget {
  const _MissingRouteArgs();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ErrorDisplayWidget(
          errorType: ErrorType.notFound,
          onRetry: () => Navigator.of(context).pop(),
        ),
      ),
    );
  }
}

/// Flutter shrinks tap targets and tightens density on desktop platforms, so a
/// narrow browser window on a laptop or a touch Chromebook got 40 px buttons
/// and 32 px chips. Below the rail breakpoint the app is a touch layout
/// whatever the platform; the desktop layout is left as it was.
class _TouchTargets extends StatelessWidget {
  const _TouchTargets({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.sizeOf(context).width >= ContentWidth.touchLayoutBelow) {
      return child;
    }
    return Theme(
      data: Theme.of(context).copyWith(
        materialTapTargetSize: MaterialTapTargetSize.padded,
        visualDensity: VisualDensity.standard,
      ),
      child: child,
    );
  }
}
