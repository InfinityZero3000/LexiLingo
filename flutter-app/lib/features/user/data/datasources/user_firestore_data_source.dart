import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/settings_model.dart';
import '../../../../core/services/firestore_service.dart';

abstract class UserFirestoreDataSource {
  Future<UserModel?> getUser(String userId);
  Future<void> createUser(UserModel user);
  Future<void> updateUser(UserModel user);
  Future<void> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  });
  Future<SettingsModel?> getSettings(String userId);
  Future<void> updateSettings(SettingsModel settings);
  Stream<UserModel?> watchUser(String userId);
}

class UserFirestoreDataSourceImpl implements UserFirestoreDataSource {
  final FirestoreService firestoreService;

  UserFirestoreDataSourceImpl({required this.firestoreService});

  @override
  Future<UserModel?> getUser(String userId) async {
    try {
      final doc = await firestoreService.getUserDocument(userId)?.get();
      if (doc == null || !doc.exists) return null;
      
      final data = doc.data() as Map<String, dynamic>;
      return UserModel.fromJson({...data, 'id': userId});
    } catch (e) {
      throw Exception('Failed to get user from Firestore: $e');
    }
  }

  @override
  Future<void> createUser(UserModel user) async {
    try {
      await firestoreService.getUserDocument(user.id)?.set({
        'name': user.name,
        'email': user.email,
        'avatarUrl': user.avatarUrl,
        'joinDate': user.joinDate.toIso8601String(),
        'lastLoginDate': user.lastLoginDate?.toIso8601String(),
        'totalXP': user.totalXP,
        'currentStreak': user.currentStreak,
        'longestStreak': user.longestStreak,
        'totalLessonsCompleted': user.totalLessonsCompleted,
        'totalWordsLearned': user.totalWordsLearned,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to create user in Firestore: $e');
    }
  }

  @override
  Future<void> updateUser(UserModel user) async {
    try {
      await firestoreService.getUserDocument(user.id)?.update({
        'name': user.name,
        'email': user.email,
        'avatarUrl': user.avatarUrl,
        'lastLoginDate': user.lastLoginDate?.toIso8601String(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update user in Firestore: $e');
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
    try {
      final Map<String, dynamic> updates = {'updatedAt': FieldValue.serverTimestamp()};
      
      if (totalXP != null) updates['totalXP'] = totalXP;
      if (currentStreak != null) updates['currentStreak'] = currentStreak;
      if (longestStreak != null) updates['longestStreak'] = longestStreak;
      if (totalLessonsCompleted != null) updates['totalLessonsCompleted'] = totalLessonsCompleted;
      if (totalWordsLearned != null) updates['totalWordsLearned'] = totalWordsLearned;
      
      await firestoreService.getUserDocument(userId)?.update(updates);
    } catch (e) {
      throw Exception('Failed to update user stats in Firestore: $e');
    }
  }

  @override
  Future<SettingsModel?> getSettings(String userId) async {
    try {
      final doc = await firestoreService.getUserDocument(userId)?.get();
      if (doc == null || !doc.exists) return null;
      
      final data = doc.data() as Map<String, dynamic>;
      final settingsData = data['settings'] as Map<String, dynamic>?;
      
      if (settingsData == null) return null;
      
      return SettingsModel.fromJson({
        ...settingsData,
        'id': 0, // Firestore doesn't use auto-increment IDs
        'userId': userId,
      });
    } catch (e) {
      throw Exception('Failed to get settings from Firestore: $e');
    }
  }

  @override
  Future<void> updateSettings(SettingsModel settings) async {
    try {
      await firestoreService.getUserDocument(settings.userId)?.update({
        'settings': {
          'notificationEnabled': settings.notificationEnabled,
          'notificationTime': settings.notificationTime,
          'theme': settings.theme,
          'language': settings.language,
          'soundEnabled': settings.soundEnabled,
          'dailyGoalXP': settings.dailyGoalXP,
        },
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      throw Exception('Failed to update settings in Firestore: $e');
    }
  }

  @override
  Stream<UserModel?> watchUser(String userId) {
    try {
      return firestoreService.getUserDocument(userId)!.snapshots().map((doc) {
        if (!doc.exists) return null;
        final data = doc.data() as Map<String, dynamic>;
        return UserModel.fromJson({...data, 'id': userId});
      });
    } catch (e) {
      throw Exception('Failed to watch user from Firestore: $e');
    }
  }
}
