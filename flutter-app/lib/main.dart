import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode, debugPrint;
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:lexilingo_app/firebase_options.dart';
import 'package:lexilingo_app/core/services/firebase_messaging_service.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/utils/app_logger.dart';
// import 'package:lexilingo_app/core/services/course_import_service.dart'; // Already disabled
import 'package:lexilingo_app/core/services/health_check_service.dart';
import 'package:lexilingo_app/core/startup/startup_coordinator.dart';
import 'package:lexilingo_app/core/startup/startup_task.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/features/achievements/presentation/providers/achievement_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/reset_password_page.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/auth_wrapper.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/story_provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import 'package:lexilingo_app/features/profile/presentation/providers/profile_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/voice_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/speech_recognition_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';
import 'package:lexilingo_app/features/youtube/presentation/providers/youtube_provider.dart';
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_explore_screen.dart';
import 'package:lexilingo_app/features/youtube/presentation/screens/youtube_player_screen.dart';
import 'package:lexilingo_app/features/youtube/domain/entities/youtube_entities.dart';

import 'package:lexilingo_app/features/news/presentation/providers/news_provider.dart';
import 'package:lexilingo_app/features/news/presentation/screens/news_list_screen.dart';
import 'package:lexilingo_app/features/news/presentation/screens/news_detail_screen.dart';
import 'package:lexilingo_app/features/news/presentation/screens/news_quiz_screen.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';

// Phase 3: English Games + XP System
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/screens/games_hub_screen.dart';

// Phase 4: Podcast
import 'package:lexilingo_app/features/podcast/presentation/providers/podcast_provider.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_explore_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_detail_screen.dart';
import 'package:lexilingo_app/features/podcast/presentation/screens/podcast_player_screen.dart';
import 'package:lexilingo_app/features/podcast/domain/entities/podcast_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:lexilingo_app/features/books/presentation/screens/book_library_screen.dart';

// Phase 6: Lexi Chat — Story Adventure
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await EasyLocalization.ensureInitialized();

  // Add error handler for Flutter and Dart errors
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    debugPrint('Flutter Error: ${details.exception}');
  };

  try {
    // Load .env.production for release builds, .env for dev
    final envFile = kReleaseMode ? '.env.production' : '.env';
    await dotenv.load(fileName: envFile);
  } catch (e) {
    debugPrint('Warning: Could not load .env file: $e');
  }

  debugPrint('Backend API base URL: ${ApiConfig.baseUrl}');
  debugPrint('AI service base URL: ${ApiConfig.aiServiceUrl}');

  // Initialize Firebase
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint('Firebase initialized successfully');

    // Initialize Firebase Cloud Messaging
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    // Push notification permission should not block app startup
    // so we delay it until after runApp()
  } catch (e) {
    debugPrint('Warning: Firebase initialization failed: $e');
  }

  // Initialize Dependency Injection (skip database on web)
  await di.initializeDependencies(skipDatabase: kIsWeb);

  // Initialize local notifications early so Settings sync can schedule reliably.
  await di.sl<NotificationService>().ensureInitialized();

  // Run startup tasks (health check, seeding). Non-blocking for web.
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
        // Commented out - CourseImportService uses old local database schema
        // Courses are now fetched from backend API
        // StartupTask(
        //   id: 'seed_courses',
        //   label: 'Seed courses if empty',
        //   action: () async {
        //     final courseImportService = di.sl<CourseImportService>();
        //     final stats = await courseImportService.getCourseStats();
        //     if (stats['total'] == 0) {
        //       await courseImportService.seedRealCourses();
        //     }
        //   },
        // ),
      ],
    );

    await coordinator.run(
      onProgress: (result) => logDebug(
        'Startup',
        '${result.id}: ${result.status.name} ${result.message ?? ''}',
      ),
    );
  }

  runApp(
    EasyLocalization(
      supportedLocales: const [
        Locale('vi'),
        Locale('en'),
        Locale('ja'),
        Locale('ko'),
      ],
      path: 'assets/i18n',
      fallbackLocale: const Locale('vi'),
      startLocale: const Locale('vi'),
      child: const LexiLingoApp(),
    ),
  );

  // Initialize Firebase Messaging after UI starts rendering
  // so the permission dialog doesn't appear over a blank screen
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    try {
      await FirebaseMessagingService.instance.initialize();
      debugPrint('Firebase Messaging initialized successfully');
    } catch (e) {
      debugPrint('Warning: Firebase Messaging initialization failed: $e');
    }
  });
}

class LexiLingoApp extends StatelessWidget {
  const LexiLingoApp({super.key});

  String? _extractResetTokenFromDeepLink() {
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
        ChangeNotifierProvider(create: (_) => di.sl<UserProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<HomeProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<ProfileProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<ChatProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<StoryProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<CourseProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<LearningProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<ProgressProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<VocabProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<FlashcardProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<VoiceProvider>()),
        ChangeNotifierProvider(
          create: (_) => di.sl<SpeechRecognitionProvider>(),
        ),
        ChangeNotifierProvider(
          create: (_) => di.sl<TtsSettingsProvider>()..init(),
        ),
        ChangeNotifierProvider(
          create: (_) => di.sl<StreakProvider>()..loadStreak(),
        ),
        ChangeNotifierProvider(
          create: (_) => di.sl<DailyChallengesProvider>()..loadChallenges(),
        ),
        ChangeNotifierProvider(create: (_) => di.sl<AchievementProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<NotificationProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<LevelProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<ProficiencyProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<SettingsProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<GamificationProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<SocialProvider>()),
        // Phase 1: YouTube Video Integration
        ChangeNotifierProvider(create: (_) => di.sl<YouTubeProvider>()),
        // Phase 2: News Reading
        ChangeNotifierProvider(create: (_) => di.sl<NewsProvider>()),
        // Phase 3: English Games + XP System
        // On web: defer XP profile load to avoid blocking startup
        ChangeNotifierProvider(
          create: (_) {
            final p = di.sl<GamesProvider>();
            if (!kIsWeb) p.loadXPProfile();
            return p;
          },
        ),
        // Phase 4: Podcast
        // On web: defer curated podcast load (AudioService not available on web)
        ChangeNotifierProvider(
          create: (_) {
            final p = di.sl<PodcastProvider>();
            if (!kIsWeb) p.loadCuratedPodcasts();
            return p;
          },
        ),
        // Phase 5: Book Reading
        ChangeNotifierProvider(create: (_) => di.sl<BookProvider>()),
        // Phase 6: Lexi Chat — Story Adventure
        ChangeNotifierProvider(create: (_) => di.sl<LexiChatProvider>()),
      ],
      child: Consumer2<SettingsProvider, AuthProvider>(
        builder: (context, settings, auth, child) {
          final safeContext = context;
          // Sync locale from settings on startup (after auth wrapper initializes)
          WidgetsBinding.instance.addPostFrameCallback((_) async {
            if (auth.currentUser != null && settings.settings != null) {
              // Sync app locale with saved settings
              final savedLocale = await LocaleService.getSavedLocale();
              if (!safeContext.mounted) return;
              final settingsLanguage = settings.language;
              
              // If settings has a different language than saved locale, update it
              if (savedLocale != settingsLanguage) {
                await LocaleService.saveLocale(settingsLanguage);
                if (!safeContext.mounted) return;
                await safeContext.setLocale(Locale(settingsLanguage));
                debugPrint('Locale synced from settings: $settingsLanguage');
              }
            }
          });
          
          return MaterialApp(
            title: 'LexiLingo',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: settings.themeMode,
            // Localization — easy_localization handles locale state
            locale: context.locale,
            supportedLocales: context.supportedLocales,
            localizationsDelegates: context.localizationDelegates,
            home: const AuthWrapper(),
            routes: {
              '/youtube': (context) => const YouTubeExploreScreen(),
              '/youtube/player': (context) {
                final video =
                    ModalRoute.of(context)!.settings.arguments as YouTubeVideo;
                return YouTubePlayerScreen(video: video);
              },
              '/news': (context) => const NewsListScreen(),
              '/news/detail': (context) {
                final article =
                    ModalRoute.of(context)!.settings.arguments as NewsArticle;
                return NewsDetailScreen(article: article);
              },
              '/news/quiz': (context) {
                final article =
                    ModalRoute.of(context)!.settings.arguments as NewsArticle;
                return NewsQuizScreen(article: article);
              },
              // Phase 3: English Games
              '/games': (context) => const GamesHubScreen(),
              // Phase 4: Podcast
              '/podcast': (context) => const PodcastExploreScreen(),
              '/podcast/detail': (context) {
                final podcast =
                    ModalRoute.of(context)!.settings.arguments as Podcast;
                return PodcastDetailScreen(podcast: podcast);
              },
              '/podcast/player': (context) {
                final args =
                    ModalRoute.of(context)!.settings.arguments
                        as Map<String, dynamic>;
                return PodcastPlayerScreen(
                  episode: args['episode'] as PodcastEpisode,
                  artworkUrl: args['artworkUrl'] as String,
                );
              },
              // Phase 5: Books
              '/books': (context) => const BookLibraryScreen(),
              // Phase 6: Lexi Chat
              '/lexi': (context) => const LexiChatPage(),
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
            },
          );
        },
      ),
    );
  }
}
