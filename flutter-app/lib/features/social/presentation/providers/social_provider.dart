import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:permission_handler/permission_handler.dart';

/// Social Provider
/// Manages followers, following, and activity feed state
class SocialProvider extends ChangeNotifier {
  late final ApiClient _apiClient;

  SocialProvider() {
    _apiClient = sl<ApiClient>();
  }

  bool _isSuccessResponse(Map<String, dynamic> response) {
    final success = response['success'];
    return success is bool ? success : true;
  }

  dynamic _extractData(Map<String, dynamic> response) {
    return response.containsKey('data') ? response['data'] : response;
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

  // ============== Suggested Friends State ==============
  List<UserSocialProfileEntity> _suggestedUsers = [];
  bool _isLoadingSuggestions = false;
  String? _suggestionsError;

  // ============== Nearby Users State (Phase 2) ==============
  List<UserSocialProfileEntity> _nearbyUsers = [];
  bool _isLoadingNearby = false;
  String? _nearbyError;
  bool _isNearbyEnabled = false;
  double _nearbyRadiusKm = 25;

  List<UserSocialProfileEntity> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  List<UserSocialProfileEntity> get suggestedUsers => _suggestedUsers;
  bool get isLoadingSuggestions => _isLoadingSuggestions;
  String? get suggestionsError => _suggestionsError;
  List<UserSocialProfileEntity> get nearbyUsers => _nearbyUsers;
  bool get isLoadingNearby => _isLoadingNearby;
  String? get nearbyError => _nearbyError;
  bool get isNearbyEnabled => _isNearbyEnabled;
  double get nearbyRadiusKm => _nearbyRadiusKm;

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

      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final activities = (data['activities'] as List? ?? [])
            .map((e) => ActivityFeedItemEntity.fromJson(e))
            .toList();

        if (refresh) {
          _activityFeed = activities;
        } else {
          _activityFeed.addAll(activities);
        }

        _hasMoreFeed = data['has_more'] ?? activities.length >= 20;
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

      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final users = (data['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();

        if (refresh) {
          _followers = users;
        } else {
          _followers.addAll(users);
        }
        _followersCount = data['total'] ?? _followers.length;
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

      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final users = (data['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();

        if (refresh) {
          _following = users;
        } else {
          _following.addAll(users);
        }
        _followingCount = data['total'] ?? _following.length;
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

      if (_isSuccessResponse(response)) {
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

      if (_isSuccessResponse(response)) {
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

    // Update in suggestions
    _suggestedUsers = _suggestedUsers.map((user) {
      if (user.userId == userId) {
        return user.copyWith(isFollowing: isFollowing);
      }
      return user;
    }).toList();

    // Update in nearby users
    _nearbyUsers = _nearbyUsers.map((user) {
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

      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is List) {
        _searchResults = data
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

  Future<void> loadSuggestedUsers({int limit = 10}) async {
    if (_isLoadingSuggestions) return;

    _isLoadingSuggestions = true;
    _suggestionsError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get(
        '/gamification/users/suggestions?limit=$limit',
      );
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final users = (data['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();
        _suggestedUsers = users;
      } else {
        _suggestionsError = 'Invalid suggestions payload';
      }
    } catch (e) {
      _suggestionsError = e.toString();
      debugPrint('Error loading friend suggestions: $e');
    } finally {
      _isLoadingSuggestions = false;
      notifyListeners();
    }
  }

  Future<void> loadNearbyUsers({int limit = 10, double radiusKm = 25}) async {
    if (_isLoadingNearby) return;

    _isLoadingNearby = true;
    _nearbyError = null;
    _nearbyRadiusKm = radiusKm;
    notifyListeners();

    try {
      final granted = await _syncLocationAndCheckPermission();
      if (!granted) {
        _nearbyUsers = [];
        _isNearbyEnabled = false;
        _nearbyError = 'Location permission denied';
        return;
      }

      final response = await _apiClient.get(
        '/gamification/users/nearby?limit=$limit&radius_km=$radiusKm',
      );
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final users = (data['users'] as List? ?? [])
            .map((e) => UserSocialProfileEntity.fromJson(e))
            .toList();
        _nearbyUsers = users;
        _isNearbyEnabled = data['location_enabled'] ?? users.isNotEmpty;
      } else {
        _nearbyError = 'Invalid nearby payload';
      }
    } catch (e) {
      _nearbyError = e.toString();
      debugPrint('Error loading nearby users: $e');
    } finally {
      _isLoadingNearby = false;
      notifyListeners();
    }
  }

  Future<void> disableNearbySharing() async {
    try {
      await _apiClient.post(
        '/gamification/users/location',
        body: {'enabled': false},
      );
      _isNearbyEnabled = false;
      _nearbyUsers = [];
      _nearbyError = null;
      notifyListeners();
    } catch (e) {
      _nearbyError = e.toString();
      debugPrint('Error disabling nearby sharing: $e');
      notifyListeners();
    }
  }

  Future<bool> _syncLocationAndCheckPermission() async {
    final locationPermission = await Permission.locationWhenInUse.request();
    if (!locationPermission.isGranted) {
      return false;
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _nearbyError = 'Location services are disabled';
      return false;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 8),
      ),
    );

    await _apiClient.post(
      '/gamification/users/location',
      body: {
        'enabled': true,
        'latitude': position.latitude,
        'longitude': position.longitude,
        'accuracy_meters': position.accuracy,
      },
    );

    return true;
  }
}
