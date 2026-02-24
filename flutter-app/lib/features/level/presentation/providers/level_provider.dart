import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/level_entity.dart';
import '../../services/level_calculator.dart';

/// Level Provider
/// Manages user level state and provides level-related functionality.
/// Supports both local calculation and remote /me/level-full API.
class LevelProvider with ChangeNotifier {
  LevelStatus _levelStatus = LevelStatus.empty();
  bool _isLoading = false;
  String? _errorMessage;
  bool _showLevelUpDialog = false;
  LevelTier? _previousTier;

  // --- Full level data from API ---
  int _numericLevel = 1;
  int _currentXpInLevel = 0;
  int _xpForNextLevel = 100;
  double _levelProgressPercent = 0;
  int _totalXp = 0;
  String _proficiencyLevel = 'A1';
  String _proficiencyName = 'Beginner';
  String _rank = 'bronze';
  String _rankName = 'Bronze';
  double _rankScore = 0;
  Map<String, dynamic> _rawLevelFull = {};

  // Getters  (local calculator based)
  LevelStatus get levelStatus => _levelStatus;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get showLevelUpDialog => _showLevelUpDialog;
  LevelTier? get previousTier => _previousTier;

  LevelTier get currentTier => _levelStatus.currentTier;
  String get levelDisplayName => _levelStatus.displayName;
  String get levelShortName => _levelStatus.shortName;
  int get totalXP => _levelStatus.totalXP;
  double get progressPercentage => _levelStatus.progressPercentage;
  int get xpToNextLevel => _levelStatus.xpToNextLevel;
  int get xpInCurrentLevel => _levelStatus.xpInCurrentLevel;
  bool get isAtMaxLevel => _levelStatus.isAtMaxLevel;
  LevelTier? get nextTier => _levelStatus.nextTier;

  // Getters (API /me/level-full based)
  int get numericLevel => _numericLevel;
  int get currentXpInLevel => _currentXpInLevel;
  int get xpForNextLevel => _xpForNextLevel;
  double get levelProgressPercent => _levelProgressPercent;
  int get totalXp => _totalXp;
  String get proficiencyLevel => _proficiencyLevel;
  String get proficiencyName => _proficiencyName;
  String get rank => _rank;
  String get rankName => _rankName;
  double get rankScore => _rankScore;
  Map<String, dynamic> get rawLevelFull => _rawLevelFull;

  /// Update level status based on total XP
  ///
  /// This recalculates the level status and triggers notifications
  /// if a level up occurred.
  void updateLevel(int totalXP) {
    final oldTier = _levelStatus.currentTier;
    _levelStatus = LevelCalculator.calculateLevelStatus(totalXP);

    // Check for level up
    if (_levelStatus.currentTier.minXP > oldTier.minXP) {
      _previousTier = oldTier;
      _showLevelUpDialog = true;
      debugPrint(
        'Level up! ${oldTier.code} -> ${_levelStatus.currentTier.code}',
      );
    }

    notifyListeners();
  }

  /// Add XP and check for level changes
  ///
  /// Returns true if the XP addition caused a level up
  bool addXP(int xpToAdd) {
    if (xpToAdd <= 0) return false;

    final oldTier = _levelStatus.currentTier;
    final newTotalXP = _levelStatus.totalXP + xpToAdd;

    updateLevel(newTotalXP);

    return _levelStatus.currentTier.minXP > oldTier.minXP;
  }

  /// Dismiss the level up dialog
  void dismissLevelUpDialog() {
    _showLevelUpDialog = false;
    _previousTier = null;
    notifyListeners();
  }

  /// Get formatted XP display string
  String getFormattedTotalXP() {
    return LevelCalculator.formatXP(_levelStatus.totalXP);
  }

  /// Get formatted XP to next level
  String getFormattedXPToNext() {
    return LevelCalculator.formatXP(_levelStatus.xpToNextLevel);
  }

  /// Get progress display string (e.g., "1,234 / 3,000 XP")
  String getProgressDisplayString() {
    if (_levelStatus.isAtMaxLevel) {
      return '${LevelCalculator.formatXP(_levelStatus.totalXP)} XP (Max Level)';
    }

    final currentLevelMaxXP = _levelStatus.currentTier.maxXP!;
    return '${LevelCalculator.formatXP(_levelStatus.totalXP)} / ${LevelCalculator.formatXP(currentLevelMaxXP + 1)} XP';
  }

  /// Get progress within current level display string
  String getLevelProgressString() {
    if (_levelStatus.isAtMaxLevel) {
      return 'Mastery Achieved';
    }

    final xpInLevel = _levelStatus.xpInCurrentLevel;
    final levelRange = _levelStatus.currentTier.xpRange;
    return '${LevelCalculator.formatXP(xpInLevel)} / ${LevelCalculator.formatXP(levelRange)} XP';
  }

  /// Get motivational message
  String getMotivationalMessage() {
    return LevelCalculator.getMotivationalMessage(_levelStatus);
  }

  /// Check if would level up with additional XP
  bool wouldLevelUp(int additionalXP) {
    return LevelCalculator.wouldLevelUp(_levelStatus.totalXP, additionalXP);
  }

  /// Get XP required to reach a specific level
  int getXPRequiredForLevel(LevelTier targetTier) {
    return LevelCalculator.getXPRequiredForLevel(
      _levelStatus.totalXP,
      targetTier,
    );
  }

  /// Reset to initial state
  void reset() {
    _levelStatus = LevelStatus.empty();
    _isLoading = false;
    _errorMessage = null;
    _showLevelUpDialog = false;
    _previousTier = null;
    _numericLevel = 1;
    _currentXpInLevel = 0;
    _xpForNextLevel = 100;
    _levelProgressPercent = 0;
    _totalXp = 0;
    _proficiencyLevel = 'A1';
    _proficiencyName = 'Beginner';
    _rank = 'bronze';
    _rankName = 'Bronze';
    _rankScore = 0;
    _rawLevelFull = {};
    notifyListeners();
  }

  // =====================
  // Remote API methods
  // =====================

  /// Fetch full level + rank data from `/users/me/level-full`.
  ///
  /// Requires an [ApiClient] instance (passed in to keep provider loosely
  /// coupled from DI container).
  Future<void> fetchLevelFull(ApiClient apiClient) async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await apiClient.get('/users/me/level-full');
      _rawLevelFull = data;
      _numericLevel = data['numeric_level'] ?? 1;
      _currentXpInLevel = data['current_xp_in_level'] ?? 0;
      _xpForNextLevel = data['xp_for_next_level'] ?? 100;
      _levelProgressPercent =
          (data['level_progress_percent'] ?? 0).toDouble();
      _totalXp = data['total_xp'] ?? 0;
      _proficiencyLevel = data['proficiency_level'] ?? 'A1';
      _proficiencyName = data['proficiency_name'] ?? 'Beginner';
      _rank = data['rank'] ?? 'bronze';
      _rankName = data['rank_name'] ?? 'Bronze';
      _rankScore = (data['rank_score'] ?? 0).toDouble();

      // Also keep local LevelStatus in sync
      updateLevel(_totalXp);
    } catch (e) {
      _errorMessage = e.toString();
      debugPrint('fetchLevelFull error: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Set loading state
  void setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  /// Set error message
  void setError(String? message) {
    _errorMessage = message;
    notifyListeners();
  }

  /// Clear error
  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }
}
