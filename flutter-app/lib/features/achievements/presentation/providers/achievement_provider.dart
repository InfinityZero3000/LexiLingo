/// Achievement Provider - State management for achievements
library;

import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/unlocked_achievement.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';

class AchievementProvider with ChangeNotifier {
  final AchievementRepository repository;

  AchievementProvider({required this.repository});

  // State
  List<AchievementEntity> _allAchievements = [];
  List<UserAchievementEntity> _myAchievements = [];
  List<UnlockedAchievement> _recentlyUnlocked = [];
  bool _isLoading = false;
  UiText? _error;

  // Getters
  List<AchievementEntity> get allAchievements => _allAchievements;
  List<UserAchievementEntity> get myAchievements => _myAchievements;
  List<UnlockedAchievement> get recentlyUnlocked => _recentlyUnlocked;
  bool get isLoading => _isLoading;
  String? get error => _error?.resolve();

  List<AchievementEntity> _removeXpAchievements(
    List<AchievementEntity> achievements,
  ) {
    return achievements
        .where((achievement) => achievement.category.toLowerCase() != 'xp')
        .toList();
  }

  List<UserAchievementEntity> _removeXpUserAchievements(
    List<UserAchievementEntity> achievements,
  ) {
    return achievements
        .where(
          (achievement) =>
              achievement.achievement.category.toLowerCase() != 'xp',
        )
        .toList();
  }

  /// Unlocked achievement IDs for quick lookup
  Set<String> get unlockedIds =>
      _myAchievements.map((ua) => ua.achievement.id).toSet();

  /// Achievements grouped by category
  Map<String, List<AchievementEntity>> get achievementsByCategory {
    final Map<String, List<AchievementEntity>> grouped = {};
    for (final achievement in _allAchievements) {
      final category = achievement.category;
      grouped.putIfAbsent(category, () => []);
      grouped[category]!.add(achievement);
    }
    return grouped;
  }

  /// Count of unlocked achievements
  int get unlockedCount => _myAchievements.length;

  /// Total achievements count
  int get totalCount => _allAchievements.length;

  /// Completion percentage
  double get completionPercentage {
    if (totalCount == 0) return 0.0;
    return (unlockedCount / totalCount * 100);
  }

  /// One counter per list: a `loadMyAchievements` fired by an unlock must not
  /// discard a `loadAll` still in flight, and within a list the newest call
  /// wins (screen, check and topic chat all reload it).
  int _allRequest = 0;
  int _mineRequest = 0;

  /// Bumped by [reset]; a response that started before it belongs to the
  /// previous account and is dropped.
  int _epoch = 0;

  /// Drops every per-user value so the next account never sees the last one's.
  void reset() {
    _epoch++;
    _allRequest++;
    _mineRequest++;
    _allAchievements = [];
    _myAchievements = [];
    _recentlyUnlocked = [];
    _isLoading = false;
    _error = null;
    _inFlight = 0;
    notifyListeners();
  }

  int _inFlight = 0;

  /// A failed load keeps the previous lists and sets [error].
  Future<void> _load({required bool all, required bool mine}) async {
    final epoch = _epoch;
    final allRequest = all ? ++_allRequest : _allRequest;
    final mineRequest = mine ? ++_mineRequest : _mineRequest;
    _inFlight++;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        if (all) repository.getAllAchievements(),
        if (mine) repository.getMyAchievements(),
      ]);
      if (epoch != _epoch) return;
      var next = 0;
      if (all) {
        final list = results[next++] as List<AchievementEntity>;
        if (allRequest == _allRequest) {
          _allAchievements = _removeXpAchievements(list);
        }
      }
      if (mine) {
        final list = results[next] as List<UserAchievementEntity>;
        if (mineRequest == _mineRequest) {
          _myAchievements = _removeXpUserAchievements(list);
        }
      }
    } catch (e) {
      if (epoch == _epoch) _error = UiText.key('errors.loadFailed');
      debugPrint('Failed to load achievements: $e');
    } finally {
      if (epoch == _epoch) {
        _inFlight--;
        _isLoading = _inFlight > 0;
        notifyListeners();
      }
    }
  }

  /// Load all achievements
  Future<void> loadAllAchievements() => _load(all: true, mine: false);

  /// Load user's unlocked achievements
  Future<void> loadMyAchievements() => _load(all: false, mine: true);

  /// Load all data
  Future<void> loadAll() => _load(all: true, mine: true);

  /// Force check all achievements and get newly unlocked
  Future<List<UnlockedAchievement>> checkAchievements() async {
    final epoch = _epoch;
    try {
      final unlocked = await repository.checkAllAchievements();
      if (epoch != _epoch) return [];
      if (unlocked.isNotEmpty) {
        _recentlyUnlocked = unlocked;
        // Reload my achievements to update the list
        await loadMyAchievements();
      }
      return unlocked;
    } catch (e) {
      debugPrint('Error checking achievements: $e');
      return [];
    }
  }

  /// Identifies the signed-in account; read it before a request and pass it
  /// back to [handleUnlockedAchievements] so a late response is ignored.
  int get sessionEpoch => _epoch;

  /// Handle newly unlocked achievements from API responses
  void handleUnlockedAchievements(
    List<dynamic> achievementsJson, {
    int? sessionEpoch,
  }) {
    if (achievementsJson.isEmpty) return;
    if (sessionEpoch != null && sessionEpoch != _epoch) return;

    _recentlyUnlocked = achievementsJson
        .map((json) => UnlockedAchievementModel.fromJson(json))
        .toList();
    notifyListeners();

    // Reload my achievements in background
    loadMyAchievements();
  }

  /// Clear recently unlocked (after showing popup)
  void clearRecentlyUnlocked() {
    _recentlyUnlocked = [];
    notifyListeners();
  }

  /// Check if an achievement is unlocked
  bool isUnlocked(String achievementId) {
    return unlockedIds.contains(achievementId);
  }

  /// Get achievements by rarity
  List<AchievementEntity> getByRarity(String rarity) {
    return _allAchievements.where((a) => a.rarity == rarity).toList();
  }
}
