import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';

/// Remote data source — thin wrapper around ApiClient.
/// All API calls for the social feature go through here.
class SocialRemoteDataSource {
  final ApiClient _apiClient;

  SocialRemoteDataSource({required ApiClient apiClient})
    : _apiClient = apiClient;

  // ── helpers ──────────────────────────────────────────────────────────────

  bool _ok(Map<String, dynamic> r) {
    final v = r['success'];
    return v is bool ? v : true;
  }

  dynamic _data(Map<String, dynamic> r) =>
      r.containsKey('data') ? r['data'] : r;

  // ── Activity Feed ─────────────────────────────────────────────────────────

  Future<({List<ActivityFeedItemEntity> activities, bool hasMore})>
  getActivityFeed({int limit = 20, int offset = 0}) async {
    final response = await _apiClient.get(
      '/gamification/feed?limit=$limit&offset=$offset',
    );
    final data = _data(response);
    if (_ok(response) && data is Map<String, dynamic>) {
      return (
        activities: (data['activities'] as List? ?? [])
            .map((e) => ActivityFeedItemEntity.fromJson(e))
            .toList(),
        hasMore: data['has_more'] as bool? ?? false,
      );
    }
    return (activities: <ActivityFeedItemEntity>[], hasMore: false);
  }

  // ── Followers / Following ────────────────────────────────────────────────

  Future<({List<UserSocialProfileEntity> users, int total})> getFollowers(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/gamification/users/$userId/followers?limit=$limit&offset=$offset',
    );
    final data = _data(response);
    if (_ok(response) && data is Map<String, dynamic>) {
      final users = (data['users'] as List? ?? [])
          .map((e) => UserSocialProfileEntity.fromJson(e))
          .toList();
      return (users: users, total: (data['total'] as int?) ?? users.length);
    }
    return (users: <UserSocialProfileEntity>[], total: 0);
  }

  Future<({List<UserSocialProfileEntity> users, int total})> getFollowing(
    String userId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/gamification/users/$userId/following?limit=$limit&offset=$offset',
    );
    final data = _data(response);
    if (_ok(response) && data is Map<String, dynamic>) {
      final users = (data['users'] as List? ?? [])
          .map((e) => UserSocialProfileEntity.fromJson(e))
          .toList();
      return (users: users, total: (data['total'] as int?) ?? users.length);
    }
    return (users: <UserSocialProfileEntity>[], total: 0);
  }

  // ── Follow / Unfollow ─────────────────────────────────────────────────────

  /// Returns `true` on success. Throws on network/server error.
  Future<bool> followUser(String userId) async {
    final response = await _apiClient.post(
      '/gamification/users/$userId/follow',
    );
    return _ok(response);
  }

  /// Returns `true` on success. Throws on network/server error.
  Future<bool> unfollowUser(String userId) async {
    final response = await _apiClient.post(
      '/gamification/users/$userId/unfollow',
    );
    return _ok(response);
  }

  // ── Suggestions ───────────────────────────────────────────────────────────

  Future<List<UserSocialProfileEntity>> getSuggestions({
    int limit = 10,
    int offset = 0,
  }) async {
    final response = await _apiClient.get(
      '/gamification/users/suggestions?limit=$limit&offset=$offset',
    );
    final data = _data(response);
    if (_ok(response) && data is Map<String, dynamic>) {
      return (data['users'] as List? ?? [])
          .map((e) => UserSocialProfileEntity.fromJson(e))
          .toList();
    }
    return [];
  }

  // ── Search ────────────────────────────────────────────────────────────────

  Future<List<UserSocialProfileEntity>> searchUsers(
    String query, {
    int limit = 20,
  }) async {
    final response = await _apiClient.get(
      '/users/search?q=${Uri.encodeQueryComponent(query)}&limit=$limit',
    );
    final data = _data(response);
    if (_ok(response) && data is List) {
      return data.map((e) => UserSocialProfileEntity.fromJson(e)).toList();
    }
    return [];
  }

  // ── Nearby ────────────────────────────────────────────────────────────────

  Future<({List<UserSocialProfileEntity> users, bool locationEnabled})>
  getNearbyUsers({int limit = 10, double radiusKm = 25}) async {
    final response = await _apiClient.get(
      '/gamification/users/nearby?limit=$limit&radius_km=$radiusKm',
    );
    final data = _data(response);
    if (_ok(response) && data is Map<String, dynamic>) {
      final users = (data['users'] as List? ?? [])
          .map((e) => UserSocialProfileEntity.fromJson(e))
          .toList();
      return (
        users: users,
        locationEnabled:
            (data['location_enabled'] as bool?) ?? users.isNotEmpty,
      );
    }
    return (users: <UserSocialProfileEntity>[], locationEnabled: false);
  }

  Future<void> updateLocation({
    required bool enabled,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    final body = <String, dynamic>{'enabled': enabled};
    if (latitude != null) body['latitude'] = latitude;
    if (longitude != null) body['longitude'] = longitude;
    if (accuracyMeters != null) body['accuracy_meters'] = accuracyMeters;
    await _apiClient.post('/gamification/users/location', body: body);
  }
}
