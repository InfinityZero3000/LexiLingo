import 'package:lexilingo_app/features/social/data/datasources/social_remote_datasource.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';

/// Repository layer — isolates Provider from raw API calls.
/// Converts data-source exceptions into typed [SocialException].
class SocialRepository {
  final SocialRemoteDataSource _remote;

  SocialRepository({required SocialRemoteDataSource remote}) : _remote = remote;

  Future<({List<ActivityFeedItemEntity> activities, bool hasMore})>
      getActivityFeed({int limit = 20, int offset = 0}) =>
          _remote.getActivityFeed(limit: limit, offset: offset);

  Future<({List<UserSocialProfileEntity> users, int total})> getFollowers(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) =>
      _remote.getFollowers(userId, limit: limit, offset: offset);

  Future<({List<UserSocialProfileEntity> users, int total})> getFollowing(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) =>
      _remote.getFollowing(userId, limit: limit, offset: offset);

  /// Returns `true` on success, throws [SocialException] on failure.
  Future<bool> followUser(String userId) async {
    try {
      final ok = await _remote.followUser(userId);
      if (!ok) throw SocialException('Failed to follow user');
      return true;
    } catch (e) {
      if (e is SocialException) rethrow;
      throw SocialException('Failed to follow user: ${_message(e)}');
    }
  }

  /// Returns `true` on success, throws [SocialException] on failure.
  Future<bool> unfollowUser(String userId) async {
    try {
      final ok = await _remote.unfollowUser(userId);
      if (!ok) throw SocialException('Failed to unfollow user');
      return true;
    } catch (e) {
      if (e is SocialException) rethrow;
      throw SocialException('Failed to unfollow user: ${_message(e)}');
    }
  }

  Future<List<UserSocialProfileEntity>> getSuggestions({
    int limit = 10,
    int offset = 0,
  }) =>
      _remote.getSuggestions(limit: limit, offset: offset);

  Future<List<UserSocialProfileEntity>> searchUsers(
    String query, {
    int limit = 20,
  }) =>
      _remote.searchUsers(query, limit: limit);

  Future<({List<UserSocialProfileEntity> users, bool locationEnabled})>
      getNearbyUsers({int limit = 10, double radiusKm = 25}) =>
          _remote.getNearbyUsers(limit: limit, radiusKm: radiusKm);

  Future<void> updateLocation({
    required bool enabled,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) =>
      _remote.updateLocation(
        enabled: enabled,
        latitude: latitude,
        longitude: longitude,
        accuracyMeters: accuracyMeters,
      );

  String _message(Object e) {
    final s = e.toString();
    // Strip "Exception:" prefix for cleaner user-facing messages
    return s.startsWith('Exception:') ? s.substring(10).trim() : s;
  }
}

class SocialException implements Exception {
  final String message;
  const SocialException(this.message);

  @override
  String toString() => message;
}
