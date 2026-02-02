import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/error/exceptions.dart';
import 'package:lexilingo_app/features/user/data/models/user_stats_model.dart';
import 'package:lexilingo_app/features/user/data/models/weekly_activity_model.dart';

/// Backend Data Source for User Stats API
abstract class UserBackendDataSource {
  /// Get user statistics from backend
  Future<UserStatsModel> getUserStats();
  
  /// Get weekly activity data
  Future<List<WeeklyActivityModel>> getWeeklyActivity();
}

class UserBackendDataSourceImpl implements UserBackendDataSource {
  final ApiClient apiClient;

  const UserBackendDataSourceImpl({required this.apiClient});

  @override
  Future<UserStatsModel> getUserStats() async {
    try {
      final response = await apiClient.get('/users/me/stats');
      return UserStatsModel.fromJson(response);
    } catch (e) {
      throw ServerException('Failed to get user stats: $e');
    }
  }

  @override
  Future<List<WeeklyActivityModel>> getWeeklyActivity() async {
    try {
      final response = await apiClient.get('/users/me/weekly-activity');
      
      // Handle response based on its structure
      List<dynamic> activitiesList;
      
      if (response is Map && response.containsKey('weekly_activity')) {
        activitiesList = response['weekly_activity'] as List<dynamic>;
      } else if (response is List) {
        activitiesList = response as List<dynamic>;
      } else {
        throw ServerException('Invalid response format for weekly activity');
      }
      
      return activitiesList
          .map((activity) => WeeklyActivityModel.fromJson(activity as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ServerException('Failed to get weekly activity: $e');
    }
  }
}
