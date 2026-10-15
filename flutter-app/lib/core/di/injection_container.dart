import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/achievements/di/achievement_di.dart';
import 'package:lexilingo_app/features/auth/di/auth_di.dart';
import 'package:lexilingo_app/features/chat/di/chat_di.dart';
import 'package:lexilingo_app/features/course/di/course_di.dart';
import 'package:lexilingo_app/features/gamification/di/gamification_di.dart';
import 'package:lexilingo_app/features/home/di/home_di.dart';
import 'package:lexilingo_app/features/learning/di/learning_di.dart';
import 'package:lexilingo_app/features/level/di/level_di.dart';
import '../../features/ielts/di/ielts_di.dart';
import 'package:lexilingo_app/features/notifications/di/notification_di.dart';
import 'package:lexilingo_app/features/profile/di/profile_di.dart';
import 'package:lexilingo_app/features/progress/di/progress_di.dart';
import 'package:lexilingo_app/features/social/di/social_di.dart';
import 'package:lexilingo_app/features/user/di/user_di.dart';
import 'package:lexilingo_app/features/vocabulary/di/vocab_di.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart';
import 'package:lexilingo_app/features/voice/di/voice_di.dart';
import 'package:lexilingo_app/features/youtube/di/youtube_di.dart';
import 'package:lexilingo_app/features/news/di/news_di.dart';
import 'package:lexilingo_app/features/games/di/games_di.dart';
import 'package:lexilingo_app/features/podcast/di/podcast_di.dart';
import 'package:lexilingo_app/features/books/di/books_di.dart';
import 'package:lexilingo_app/features/lexi_chat/di/lexi_chat_di.dart';

export 'service_locator.dart';

/// Orchestrates dependency registration across core and feature modules.
Future<void> initializeDependencies({bool skipDatabase = false}) async {
  await registerCore(skipDatabase: skipDatabase);

  registerVocabModule(skipDatabase: skipDatabase);
  setupVocabularyDependencies(); // Flashcard system with SRS
  registerAuthModule();
  registerChatModule(skipDatabase: skipDatabase);
  registerCourseModule(skipDatabase: skipDatabase);
  registerLearningModule();
  registerProgressModule();
  registerUserModule(skipDatabase: skipDatabase);
  registerHomeModule();
  registerProfileModule(); // Profile stats system
  registerAchievementModule(); // Achievement/Badge system
  registerNotificationModule(); // Notification system
  registerLevelModule(); // Level/XP system
  registerIeltsModule(); // IELTS mock tests
  registerGamificationModule(); // Shop, Wallet, Leaderboard
  registerSocialModule(); // Friends, Activity Feed
  initVoiceDependencies(sl);
  registerYouTubeModule(); // Phase 1: YouTube Video Integration
  registerNewsModule(); // Phase 2: News Reading
  registerGamesModule(); // Phase 3: English Games + XP System
  await registerPodcastModule(); // Phase 4: Podcast — async (AudioService.init)
  registerBooksModule(); // Phase 5: Book Reading
  registerLexiChatModule(); // Phase 6: Lexi Chat — Story Adventure
}
