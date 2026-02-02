import 'dart:async';
import '../../features/user/data/datasources/user_local_data_source.dart';
import '../../features/user/data/datasources/user_firestore_data_source.dart';
import '../../features/user/data/models/user_model.dart';
import 'progress_firestore_data_source.dart';
import 'firestore_service.dart';
import '../utils/app_logger.dart';

/// Service for syncing local SQLite data to Firestore
class ProgressSyncService {
  final UserLocalDataSource userLocalDataSource;
  final UserFirestoreDataSource userFirestoreDataSource;
  final ProgressFirestoreDataSource progressFirestoreDataSource;
  final FirestoreService firestoreService;

  ProgressSyncService({
    required this.userLocalDataSource,
    required this.userFirestoreDataSource,
    required this.progressFirestoreDataSource,
    required this.firestoreService,
  });

  // Use firestoreService to get current user ID safely
  String? get _currentUserId => firestoreService.currentUserId;

  /// Check if device is online and Firestore is accessible
  Future<bool> isOnline() async {
    try {
      return await firestoreService.checkConnection();
    } catch (e) {
      return false;
    }
  }

  /// Sync user profile from local to Firestore
  Future<void> syncUserProfile() async {
    if (_currentUserId == null) return;
    if (!await isOnline()) return;

    try {
      final localUser = await userLocalDataSource.getUser(_currentUserId!);
      if (localUser != null) {
        await userFirestoreDataSource.updateUser(UserModel.fromEntity(localUser));
      }
    } catch (e) {
      // Log error but don't throw
      print('Failed to sync user profile: $e');
    }
  }

  /// Sync user stats from local to Firestore
  Future<void> syncUserStats() async {
    if (_currentUserId == null) return;
    if (!await isOnline()) return;

    try {
      final localUser = await userLocalDataSource.getUser(_currentUserId!);
      if (localUser != null) {
        await userFirestoreDataSource.updateUserStats(
          userId: _currentUserId!,
          totalXP: localUser.totalXP,
          currentStreak: localUser.currentStreak,
          longestStreak: localUser.longestStreak,
          totalLessonsCompleted: localUser.totalLessonsCompleted,
          totalWordsLearned: localUser.totalWordsLearned,
        );
      }
    } catch (e) {
      print('Failed to sync user stats: $e');
    }
  }

  /// Pull user data from Firestore to local
  Future<void> pullUserData() async {
    if (_currentUserId == null) return;
    if (!await isOnline()) return;

    try {
      final firestoreUser = await userFirestoreDataSource.getUser(_currentUserId!);
      if (firestoreUser != null) {
        // Check if local user exists
        final localUser = await userLocalDataSource.getUser(_currentUserId!);
        
        if (localUser == null) {
          // First time on this device, create local copy
          await userLocalDataSource.createUser(UserModel.fromEntity(firestoreUser));
        } else {
          // Merge: Keep higher values (conflict resolution)
          final mergedUser = UserModel(
            id: _currentUserId!,
            name: firestoreUser.name,
            email: firestoreUser.email,
            avatarUrl: firestoreUser.avatarUrl,
            joinDate: localUser.joinDate,
            lastLoginDate: DateTime.now(),
            totalXP: firestoreUser.totalXP > localUser.totalXP ? firestoreUser.totalXP : localUser.totalXP,
            currentStreak: firestoreUser.currentStreak > localUser.currentStreak ? firestoreUser.currentStreak : localUser.currentStreak,
            longestStreak: firestoreUser.longestStreak > localUser.longestStreak ? firestoreUser.longestStreak : localUser.longestStreak,
            totalLessonsCompleted: firestoreUser.totalLessonsCompleted > localUser.totalLessonsCompleted ? firestoreUser.totalLessonsCompleted : localUser.totalLessonsCompleted,
            totalWordsLearned: firestoreUser.totalWordsLearned > localUser.totalWordsLearned ? firestoreUser.totalWordsLearned : localUser.totalWordsLearned,
          );
          
          await userLocalDataSource.updateUser(mergedUser);
        }
      }
    } catch (e) {
      print('Failed to pull user data: $e');
    }
  }

  /// Full sync: Pull first, then push
  Future<void> fullSync() async {
    if (_currentUserId == null) return;
    if (!await isOnline()) return;

    try {
      // Pull latest data from cloud
      await pullUserData();
      
      // Push any local changes
      await syncUserProfile();
      await syncUserStats();
    } catch (e) {
      print('Failed to perform full sync: $e');
    }
  }

  /// Setup periodic background sync
  void startPeriodicSync({Duration interval = const Duration(minutes: 5)}) {
    Timer.periodic(interval, (timer) async {
      if (await isOnline()) {
        await fullSync();
      }
    });
  }

  /// Sync on app resume
  Future<void> syncOnResume() async {
    await fullSync();
  }

  /// Force immediate sync
  Future<void> forceSyncNow() async {
    await fullSync();
  }
}
