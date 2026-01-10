import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:lexilingo_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_local_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/data/repositories/chat_repository_impl.dart';
import 'package:lexilingo_app/features/chat/presentation/providers/chat_provider.dart';
import 'package:lexilingo_app/features/course/data/datasources/course_local_data_source.dart';
import 'package:lexilingo_app/features/course/data/repositories/course_repository_impl.dart';
import 'package:lexilingo_app/features/course/presentation/providers/course_provider.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';
import 'package:lexilingo_app/features/vocabulary/data/repositories/vocab_repository_impl.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final notificationService = NotificationService();
  await notificationService.init();

  // Initialize DB (lazy)
  final dbHelper = DatabaseHelper.instance;
  await dbHelper.database;

  runApp(LexiLingoApp(dbHelper: dbHelper));
}

class LexiLingoApp extends StatelessWidget {
  final DatabaseHelper dbHelper;
  const LexiLingoApp({super.key, required this.dbHelper});

  @override
  Widget build(BuildContext context) {
    // Dependency Injection
    // 1. Auth Feature
    final authRemoteDataSource = AuthRemoteDataSource();
    final authRepository = AuthRepositoryImpl(remoteDataSource: authRemoteDataSource);

    // 2. Chat Feature
    final chatLocalDataSource = ChatLocalDataSource(dbHelper: dbHelper);
    final chatRemoteDataSource = ChatRemoteDataSource(apiKey: 'YOUR_API_KEY');
    final chatRepository = ChatRepositoryImpl(remoteDataSource: chatRemoteDataSource, localDataSource: chatLocalDataSource);

    // 3. Course Feature
    final courseLocalDataSource = CourseLocalDataSource(dbHelper: dbHelper);
    final courseRepository = CourseRepositoryImpl(localDataSource: courseLocalDataSource);

    // 4. Vocab Feature
    final vocabLocalDataSource = VocabLocalDataSource(dbHelper: dbHelper);
    final vocabRepository = VocabRepositoryImpl(localDataSource: vocabLocalDataSource);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => AuthProvider(repository: authRepository)),
        ChangeNotifierProvider(create: (_) => ChatProvider(repository: chatRepository)),
        ChangeNotifierProvider(create: (_) => CourseProvider(repository: courseRepository)),
        ChangeNotifierProvider(create: (_) => VocabProvider(repository: vocabRepository)),
      ],
      child: MaterialApp(
        title: 'LexiLingo',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: ThemeMode.system,
        home: const MainScreen(),
      ),
    );
  }
}

