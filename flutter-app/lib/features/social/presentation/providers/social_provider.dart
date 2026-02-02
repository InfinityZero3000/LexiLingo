import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';

/// Social Provider
/// Manages followers, following, and activity feed state
class SocialProvider extends ChangeNotifier {
  late final ApiClient _apiClient;

  SocialProvider() {
    _apiClient = sl<ApiClient>();
  }

  // ============== Activity Feed State ==============
  List<ActivityFeedItemEntity> _activityFeed = [];
  bool _isLoadingFeed = false;
  String? _feedError;
  bool _hasMoreFeed = true;

  List<ActivityFeedItemEntity> get activityFeed => _activityFeed;
  bool get isLoadingFeed => _isLoadingFeed;
  String? get feedError => _feedError;
  bool get hasMoreFeed => _hasMoreFeed;

  // ============== Followers State ==============
  List<UserSocialProfileEntity> _followers = [];
  List<UserSocialProfileEntity> _following = [];
  bool _isLoadingFollowers = false;
  bool _isLoadingFollowing = false;
  int _followersCount = 0;
  int _followingCount = 0;

  List<UserSocialProfileEntity> get followers => _followers;
  List<UserSocialProfileEntity> get following => _following;
  bool get isLoadingFollowers => _isLoadingFollowers;
  bool get isLoadingFollowing => _isLoadingFollowing;
  int get followersCount => _followersCount;
  int get followingCount => _followingCount;

  // ============== Search State ==============
  List<UserSocialProfileEntity> _searchResults = [];
  bool _isSearching = false;
  String _searchQuery = '';

  List<UserSocialProfileEntity> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;

  // ============== Activity Feed Methods ==============
  Future<void> loadActivityFeed({bool refresh = false}) async {
    if (_isLoadingFeed) return;

    _isLoadingFeed = true;
    _feedError = null;
    if (refresh) {
      _activityFeed = [];
      _hasMoreFeed = true;
    }
    notifyListeners();

    try {
      final offset = refresh ? 0 : _activityFeed.length;
      final response = await _apiClient.get(
        '/gamification/feed?limit=20&offset=$offset',
      );

      if (response['success'] == true && response['data'] != null) {
        final activities = (response['data']['activities'] as List? ?? [])
            .map((e) => ActivityFeedItemEntity.fromJson(e))
            .toList();

        if (refresh) {
          _activityFeed = activities;
        } else {
          _activityFeed.addAll(activities);
        }

        _hasMoreFeed = response['data']['has_more'] ?? activities.length >= 20;
      }
    } catch (e) {
      _feedError = e.toString();
      debugPrint('Error loading activity feed: $e');
    } finally {
      _isLoadingFeed = false;
      notifyListeners();
    }
  }

  // ============== Followers Methods ==============
  Future<void> loadFollowers(String userId, {bool refresh = false}) async {
    if (_isLoadingFollowers) return;

    _isLoadingFollowers = true;
    if (refresh) _followers = [];
    notifyListeners();

    try {
      final offset = refresh ? 0 : _followers.length;
      final response = await _apiClient.get(
        '/gamification/users/$userId/followers?limit=50&offset=$offset',
      );

      if (response['success'] == true && response['data'] != null) {
        final users = (response['data']['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();

        if (refresh) {
          _followers = users;
        } else {
          _followers.addAll(users);
        }
        _followersCount = response['data']['total'] ?? _followers.length;
      }
    } catch (e) {
      debugPrint('Error loading followers: $e');
    } finally {
      _isLoadingFollowers = false;
      notifyListeners();
    }
  }

  Future<void> loadFollowing(String userId, {bool refresh = false}) async {
    if (_isLoadingFollowing) return;

    _isLoadingFollowing = true;
    if (refresh) _following = [];
    notifyListeners();

    try {
      final offset = refresh ? 0 : _following.length;
      final response = await _apiClient.get(
        '/gamification/users/$userId/following?limit=50&offset=$offset',
      );

      if (response['success'] == true && response['data'] != null) {
        final users = (response['data']['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();

        if (refresh) {
          _following = users;
        } else {
          _following.addAll(users);
        }
        _followingCount = response['data']['total'] ?? _following.length;
      }
    } catch (e) {
      debugPrint('Error loading following: $e');
    } finally {
      _isLoadingFollowing = false;
      notifyListeners();
    }
  }

  // ============== Follow/Unfollow Methods ==============
  Future<bool> followUser(String userId) async {
    try {
      final response = await _apiClient.post(
        '/gamification/users/$userId/follow',
      );

      if (response['success'] == true) {
        // Update local state
        _updateFollowState(userId, true);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error following user: $e');
      return false;
    }
  }

  Future<bool> unfollowUser(String userId) async {
    try {
      // Using POST with action parameter since DELETE not available
      final response = await _apiClient.post(
        '/gamification/users/$userId/unfollow',
      );

      if (response['success'] == true) {
        _updateFollowState(userId, false);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
      return false;
    }
  }

  void _updateFollowState(String userId, bool isFollowing) {
    // Update in followers list
    _followers = _followers.map((user) {
      if (user.userId == userId) {
        return user.copyWith(isFollowing: isFollowing);
      }
      return user;
    }).toList();

    // Update in following list
    _following = _following.map((user) {
      if (user.userId == userId) {
        return user.copyWith(isFollowing: isFollowing);
      }
      return user;
    }).toList();

    // Update in search results
    _searchResults = _searchResults.map((user) {
      if (user.userId == userId) {
        return user.copyWith(isFollowing: isFollowing);
      }
      return user;
    }).toList();

    notifyListeners();
  }

  // ============== Search Methods ==============
  Future<void> searchUsers(String query) async {
    if (query.length < 2) {
      _searchResults = [];
      _searchQuery = '';
      notifyListeners();
      return;
    }

    _isSearching = true;
    _searchQuery = query;
    notifyListeners();

    try {
      final response = await _apiClient.get(
        '/users/search?q=${Uri.encodeQueryComponent(query)}&limit=20',
      );

      if (response['success'] == true && response['data'] != null) {
        _searchResults = (response['data'] as List)
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();
      }
    } catch (e) {
      debugPrint('Error searching users: $e');
      _searchResults = [];
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _searchQuery = '';
    notifyListeners();
  }
}
