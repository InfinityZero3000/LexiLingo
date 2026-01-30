/// Achievement Remote Datasource
/// Handles API calls for achievements

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

abstract class AchievementRemoteDataSource {
  /// Get all available achievements
  Future<List<AchievementModel>> getAllAchievements();

  /// Get current user's unlocked achievements
  Future<List<UserAchievementModel>> getMyAchievements();

  /// Force check all achievements for current user
  Future<List<UnlockedAchievementModel>> checkAllAchievements();
}

class AchievementRemoteDataSourceImpl implements AchievementRemoteDataSource {
  final ApiClient apiClient;

  AchievementRemoteDataSourceImpl({required this.apiClient});

  @override
  Future<List<AchievementModel>> getAllAchievements() async {
    try {
      final data = await apiClient.get('/gamification/achievements');

      if (data['success'] == true && data['data'] != null) {
        final List<dynamic> achievementsList = data['data'];
        return achievementsList
            .map((json) => AchievementModel.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching achievements: $e');
      return [];
    }
  }

  @override
  Future<List<UserAchievementModel>> getMyAchievements() async {
    try {
      final data = await apiClient.get('/gamification/achievements/me');

      if (data['success'] == true && data['data'] != null) {
        final List<dynamic> achievementsList = data['data'];
        return achievementsList
            .map((json) => UserAchievementModel.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error fetching my achievements: $e');
      return [];
    }
  }

  @override
  Future<List<UnlockedAchievementModel>> checkAllAchievements() async {
    try {
      final data = await apiClient.post('/gamification/achievements/check');

      if (data['success'] == true && data['data'] != null) {
        final List<dynamic> unlockedList = data['data'];
        return unlockedList
            .map((json) => UnlockedAchievementModel.fromJson(json))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('Error checking achievements: $e');
      return [];
    }
  }
}
