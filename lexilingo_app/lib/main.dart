import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:lexilingo_app/firebase_options.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/di/injection_container.dart' as di;
import 'package:lexilingo_app/core/services/course_import_service.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/auth_wrapper.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/user_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Load environment variables from .env file
  await dotenv.load(fileName: ".env");
  
  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  
  // Initialize Dependency Injection (skip database on web)
  await di.initializeDependencies(skipDatabase: kIsWeb);

  // Seed real course data if database is empty (not on web)
  if (!kIsWeb) {
    try {
      final courseImportService = di.sl<CourseImportService>();
      final stats = await courseImportService.getCourseStats();
      
      if (stats['total'] == 0) {
        print('📚 Database empty, seeding real courses...');
        await courseImportService.seedRealCourses();
      } else {
        print('Found ${stats['total']} courses in database');
      }
    } catch (e) {
      print('Failed to seed courses: $e');
    }
  }

  runApp(const LexiLingoApp());
}

class LexiLingoApp extends StatelessWidget {
  const LexiLingoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => di.sl<AuthProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<UserProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<HomeProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<ChatProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<CourseProvider>()),
        ChangeNotifierProvider(create: (_) => di.sl<VocabProvider>()),
      ],
      child: MaterialApp(
        title: 'LexiLingo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const AuthWrapper(),
      ),
    );
  }
}

