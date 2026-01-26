import '../../domain/entities/user.dart';
import '../../domain/repositories/user_repository.dart';
import '../datasources/user_local_data_source.dart';
import '../datasources/user_firestore_data_source.dart';
import '../models/user_model.dart';

class UserRepositoryImpl implements UserRepository {
  final UserLocalDataSource localDataSource;
  final UserFirestoreDataSource? firestoreDataSource;

  UserRepositoryImpl({
    required this.localDataSource,
    this.firestoreDataSource,
  });

  @override
  Future<User?> getUser(String userId) async {
    // Offline-first: Try local first
    var user = await localDataSource.getUser(userId);
    
    // If not in local and have internet, try Firestore
    if (user == null && firestoreDataSource != null) {
      try {
        user = await firestoreDataSource!.getUser(userId);
        // Cache to local
        if (user != null) {
          await localDataSource.createUser(UserModel.fromEntity(user));
        }
      } catch (e) {
        // Firestore failed, return null
      }
    }
    
    return user;
  }

  @override
  Future<void> createUser(User user) async {
    final userModel = UserModel.fromEntity(user);
    
    // Write to local first
    await localDataSource.createUser(userModel);
    
    // Sync to Firestore if available
    if (firestoreDataSource != null) {
      try {
        await firestoreDataSource!.createUser(userModel);
      } catch (e) {
        // Sync failed, will retry later
      }
    }
  }

  @override
  Future<void> updateUser(User user) async {
    final userModel = UserModel.fromEntity(user);
    
    // Write to local first
    await localDataSource.updateUser(userModel);
    
    // Sync to Firestore if available
    if (firestoreDataSource != null) {
      try {
        await firestoreDataSource!.updateUser(userModel);
      } catch (e) {
        // Sync failed, will retry later
      }
    }
  }

  @override
  Future<void> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  }) async {
    // Write to local first
    await localDataSource.updateUserStats(
      userId: userId,
      totalXP: totalXP,
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      totalLessonsCompleted: totalLessonsCompleted,
      totalWordsLearned: totalWordsLearned,
    );
    
    // Sync to Firestore if available
    if (firestoreDataSource != null) {
      try {
        await firestoreDataSource!.updateUserStats(
          userId: userId,
          totalXP: totalXP,
          currentStreak: currentStreak,
          longestStreak: longestStreak,
          totalLessonsCompleted: totalLessonsCompleted,
          totalWordsLearned: totalWordsLearned,
        );
      } catch (e) {
        // Sync failed, will retry later
      }
    }
  }

  @override
  Future<void> updateLastLogin(String userId) async {
    await localDataSource.updateLastLogin(userId);
    
    // Update in Firestore
    if (firestoreDataSource != null) {
      try {
        final user = await localDataSource.getUser(userId);
        if (user != null) {
          await firestoreDataSource!.updateUser(UserModel.fromEntity(user));
        }
      } catch (e) {
        // Sync failed
      }
    }
  }
}
