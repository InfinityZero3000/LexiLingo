import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'user_local_data_source.dart';
import '../models/user_model.dart';

/// Web implementation of UserLocalDataSource using SharedPreferences
class UserLocalDataSourceWeb implements UserLocalDataSource {
  final SharedPreferences sharedPreferences;
  
  static const String _userKey = 'cached_user_';
  
  UserLocalDataSourceWeb({required this.sharedPreferences});

  @override
  Future<UserModel?> getUser(String userId) async {
    final jsonString = sharedPreferences.getString('$_userKey$userId');
    if (jsonString != null) {
      return UserModel.fromJson(json.decode(jsonString));
    }
    return null;
  }

  @override
  Future<int> createUser(UserModel user) async {
    await sharedPreferences.setString(
      '$_userKey${user.id}',
      json.encode(user.toJson()),
    );
    return 1; // Success
  }

  @override
  Future<int> updateUser(UserModel user) async {
    await sharedPreferences.setString(
      '$_userKey${user.id}',
      json.encode(user.toJson()),
    );
    return 1; // Success
  }

  @override
  Future<int> updateUserStats({
    required String userId,
    int? totalXP,
    int? currentStreak,
    int? longestStreak,
    int? totalLessonsCompleted,
    int? totalWordsLearned,
  }) async {
    final user = await getUser(userId);
    if (user == null) return 0;
    
    final updatedUser = UserModel(
      id: user.id,
      name: user.name,
      email: user.email,
      avatarUrl: user.avatarUrl,
      joinDate: user.joinDate,
      lastLoginDate: user.lastLoginDate,
      totalXP: totalXP ?? user.totalXP,
      currentStreak: currentStreak ?? user.currentStreak,
      longestStreak: longestStreak ?? user.longestStreak,
      totalLessonsCompleted: totalLessonsCompleted ?? user.totalLessonsCompleted,
      totalWordsLearned: totalWordsLearned ?? user.totalWordsLearned,
    );
    
    return await updateUser(updatedUser);
  }

  @override
  Future<int> updateLastLogin(String userId) async {
    final user = await getUser(userId);
    if (user == null) return 0;
    
    final updatedUser = UserModel(
      id: user.id,
      name: user.name,
      email: user.email,
      avatarUrl: user.avatarUrl,
      joinDate: user.joinDate,
      lastLoginDate: DateTime.now(),
      totalXP: user.totalXP,
      currentStreak: user.currentStreak,
      longestStreak: user.longestStreak,
      totalLessonsCompleted: user.totalLessonsCompleted,
      totalWordsLearned: user.totalWordsLearned,
    );
    
    return await updateUser(updatedUser);
  }
}
