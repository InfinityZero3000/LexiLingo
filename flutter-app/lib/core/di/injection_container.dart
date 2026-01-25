import 'package:lexilingo_app/core/di/core_di.dart';
import 'package:lexilingo_app/features/auth/di/auth_di.dart';
import 'package:lexilingo_app/features/chat/di/chat_di.dart';
import 'package:lexilingo_app/features/course/di/course_di.dart';
import 'package:lexilingo_app/features/home/di/home_di.dart';
import 'package:lexilingo_app/features/progress/di/progress_di.dart';
import 'package:lexilingo_app/features/user/di/user_di.dart';
import 'package:lexilingo_app/features/vocabulary/di/vocab_di.dart';

export 'service_locator.dart';

/// Orchestrates dependency registration across core and feature modules.
Future<void> initializeDependencies({bool skipDatabase = false}) async {
  await registerCore(skipDatabase: skipDatabase);

  registerVocabModule(skipDatabase: skipDatabase);
  registerAuthModule();
  registerChatModule(skipDatabase: skipDatabase);
  registerCourseModule(skipDatabase: skipDatabase);
  registerProgressModule();
  registerUserModule(skipDatabase: skipDatabase);
  registerHomeModule();
}

