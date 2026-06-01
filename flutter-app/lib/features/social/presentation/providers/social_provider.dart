import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:permission_handler/permission_handler.dart';

/// Social Provider
/// Manages followers, following, and activity feed state
class SocialProvider extends ChangeNotifier {
  final SocialRepository _repo;

  SocialProvider({required SocialRepository repository}) : _repo = repository;

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
  String? _searchError;

  // ============== Suggested Friends State ==============
  List<UserSocialProfileEntity> _suggestedUsers = [];
  bool _isLoadingSuggestions = false;
  String? _suggestionsError;
  bool _hasMoreSuggestions = true;

  // ============== Nearby Users State (Phase 2) ==============
  List<UserSocialProfileEntity> _nearbyUsers = [];
  bool _isLoadingNearby = false;
  String? _nearbyError;
  bool _isNearbyEnabled = false;
  double _nearbyRadiusKm = 25;

  List<UserSocialProfileEntity> get searchResults => _searchResults;
  bool get isSearching => _isSearching;
  String get searchQuery => _searchQuery;
  String? get searchError => _searchError;
  List<UserSocialProfileEntity> get suggestedUsers => _suggestedUsers;
  bool get isLoadingSuggestions => _isLoadingSuggestions;
  String? get suggestionsError => _suggestionsError;
  bool get hasMoreSuggestions => _hasMoreSuggestions;
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
      final result = await _repo.getActivityFeed(limit: 20, offset: offset);

      if (refresh) {
        _activityFeed = result.activities;
      } else {
        _activityFeed.addAll(result.activities);
      }
      _hasMoreFeed = result.hasMore;
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
      final result = await _repo.getFollowers(
        userId,
        limit: 50,
        offset: offset,
      );

      if (refresh) {
        _followers = result.users;
      } else {
        _followers.addAll(result.users);
      }
      _followersCount = result.total;
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
      final result = await _repo.getFollowing(
        userId,
        limit: 50,
        offset: offset,
      );

      if (refresh) {
        _following = result.users;
      } else {
        _following.addAll(result.users);
      }
      _followingCount = result.total;
    } catch (e) {
      debugPrint('Error loading following: $e');
    } finally {
      _isLoadingFollowing = false;
      notifyListeners();
    }
  }

  // ============== Follow/Unfollow Methods ==============

  /// Returns `null` on success, or an error message string to show as SnackBar.
  Future<String?> followUser(String userId) async {
    try {
      await _repo.followUser(userId);
      _updateFollowState(userId, true);
      return null;
    } catch (e) {
      debugPrint('Error following user: $e');
      return e.toString();
    }
  }

  /// Returns `null` on success, or an error message string to show as SnackBar.
  Future<String?> unfollowUser(String userId) async {
    try {
      await _repo.unfollowUser(userId);
      _updateFollowState(userId, false);
      return null;
    } catch (e) {
      debugPrint('Error unfollowing user: $e');
      return e.toString();
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
    _searchError = null;
    notifyListeners();

    try {
      _searchResults = await _repo.searchUsers(query);
    } catch (e) {
      debugPrint('Error searching users: $e');
      _searchResults = [];
      _searchError = 'Could not search users. Please try again.';
    } finally {
      _isSearching = false;
      notifyListeners();
    }
  }

  void clearSearch() {
    _searchResults = [];
    _searchQuery = '';
    _searchError = null;
    notifyListeners();
  }

  Future<void> loadSuggestedUsers({
    int limit = 10,
    bool refresh = false,
  }) async {
    if (_isLoadingSuggestions) return;

    _isLoadingSuggestions = true;
    _suggestionsError = null;
    if (refresh) {
      _suggestedUsers = [];
      _hasMoreSuggestions = true;
    }
    notifyListeners();

    try {
      final offset = refresh ? 0 : _suggestedUsers.length;
      final users = await _repo.getSuggestions(limit: limit, offset: offset);

      if (refresh) {
        _suggestedUsers = users;
      } else {
        _suggestedUsers.addAll(users);
      }
      _hasMoreSuggestions = users.length >= limit;
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

      final result = await _repo.getNearbyUsers(
        limit: limit,
        radiusKm: radiusKm,
      );
      _nearbyUsers = result.users;
      _isNearbyEnabled = result.locationEnabled;
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
      await _repo.updateLocation(enabled: false);
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
    if (!locationPermission.isGranted) return false;

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

    await _repo.updateLocation(
      enabled: true,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
    );

    return true;
  }
}
