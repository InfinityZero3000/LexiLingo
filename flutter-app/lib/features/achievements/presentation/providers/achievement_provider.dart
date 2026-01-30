/// Achievement Provider - State management for achievements

import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/features/achievements/domain/entities/achievement_entity.dart';
import 'package:lexilingo_app/features/achievements/domain/repositories/achievement_repository.dart';
import 'package:lexilingo_app/features/achievements/data/models/achievement_model.dart';

class AchievementProvider with ChangeNotifier {
  final AchievementRepository repository;

  AchievementProvider({required this.repository});

  // State
  List<AchievementEntity> _allAchievements = [];
  List<UserAchievementEntity> _myAchievements = [];
  List<UnlockedAchievementModel> _recentlyUnlocked = [];
  bool _isLoading = false;
  String? _error;

  // Getters
  List<AchievementEntity> get allAchievements => _allAchievements;
  List<UserAchievementEntity> get myAchievements => _myAchievements;
  List<UnlockedAchievementModel> get recentlyUnlocked => _recentlyUnlocked;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Unlocked achievement IDs for quick lookup
  Set<String> get unlockedIds => _myAchievements.map((ua) => ua.achievement.id).toSet();

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

  /// Load all achievements
  Future<void> loadAllAchievements() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _allAchievements = await repository.getAllAchievements();
    } catch (e) {
      _error = 'Failed to load achievements: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load user's unlocked achievements
  Future<void> loadMyAchievements() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _myAchievements = await repository.getMyAchievements();
    } catch (e) {
      _error = 'Failed to load my achievements: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load all data
  Future<void> loadAll() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final results = await Future.wait([
        repository.getAllAchievements(),
        repository.getMyAchievements(),
      ]);

      _allAchievements = results[0] as List<AchievementEntity>;
      _myAchievements = results[1] as List<UserAchievementEntity>;
    } catch (e) {
      _error = 'Failed to load achievements: $e';
      debugPrint(_error);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Force check all achievements and get newly unlocked
  Future<List<UnlockedAchievementModel>> checkAchievements() async {
    try {
      final unlocked = await repository.checkAllAchievements();
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

  /// Handle newly unlocked achievements from API responses
  void handleUnlockedAchievements(List<dynamic> achievementsJson) {
    if (achievementsJson.isEmpty) return;

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
