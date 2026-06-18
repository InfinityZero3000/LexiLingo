import 'package:flutter/foundation.dart';
import '../../../../core/network/api_client.dart';
import '../../domain/entities/level_entity.dart';
import '../../domain/services/level_calculator.dart';

class LevelProvider with ChangeNotifier {
  final ApiClient _apiClient;

  LevelProvider({required ApiClient apiClient}) : _apiClient = apiClient;

  LevelStatus _levelStatus = LevelStatus.empty();
  bool _isLoading = false;
  String? _errorMessage;
  bool _showLevelUpDialog = false;
  LevelTier? _previousTier;
  bool _showRankUpDialog = false;
  String? _previousRank;

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
  bool get showRankUpDialog => _showRankUpDialog;
  String? get previousRank => _previousRank;

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

  /// Numeric level for display — uses API value if available, else computed
  /// from XP using the same formula as backend: floor(100 * level^1.5).
  int get displayLevel {
    if (_numericLevel > 1) return _numericLevel;
    return LevelCalculator.calculateNumericLevel(_levelStatus.totalXP);
  }

  /// Level progress percentage (0.0–1.0) for the numeric level system.
  /// Uses API value if available, else computed with backend formula.
  double get displayLevelProgress {
    if (_levelProgressPercent > 0) {
      return (_levelProgressPercent / 100).clamp(0.0, 1.0);
    }
    return LevelCalculator.numericLevelProgressPercent(_levelStatus.totalXP);
  }

  /// XP accumulated within the current numeric level.
  int get displayXpInLevel {
    if (_numericLevel > 1) return _currentXpInLevel;
    return LevelCalculator.xpInCurrentNumericLevel(_levelStatus.totalXP);
  }

  /// XP needed to complete the current numeric level (= xp for that level).
  int get displayXpForNextLevel {
    if (_xpForNextLevel > 0 && _numericLevel > 1) return _xpForNextLevel;
    return LevelCalculator.xpForSingleLevel(displayLevel);
  }

  /// Update level status from local XP — used as offline fallback.
  ///
  /// Syncs both the CEFR [_levelStatus] and the numeric level fields so that
  /// the display getters (displayLevel, displayLevelProgress, etc.) work
  /// correctly even without a network call.
  ///
  /// Prefer calling [fetchLevelFull] when a network connection is available so
  /// the authoritative backend values are used instead.
  void updateLevel(int totalXP) {
    final oldTier = _levelStatus.currentTier;
    _levelStatus = LevelCalculator.calculateLevelStatus(totalXP);

    // Also sync numeric fields as offline fallback.
    // These will be overwritten by fetchLevelFull() when online.
    _totalXp = totalXP;
    _numericLevel = LevelCalculator.calculateNumericLevel(totalXP);
    _currentXpInLevel = LevelCalculator.xpInCurrentNumericLevel(totalXP);
    _xpForNextLevel = LevelCalculator.xpForSingleLevel(_numericLevel);
    _levelProgressPercent =
        LevelCalculator.numericLevelProgressPercent(totalXP) * 100;

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

  /// Add XP and check for level changes.
  ///
  /// @deprecated XP is owned by the backend. Call the `/users/me/xp` endpoint
  /// to award XP, then refresh via [fetchLevelFull]. This method only mutates
  /// local state and will be out of sync with the server after a page reload.
  @Deprecated(
    'XP is owned by the backend. Award XP via the API and call fetchLevelFull() to refresh.',
  )
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

  /// Dismiss the rank up dialog
  void dismissRankUpDialog() {
    _showRankUpDialog = false;
    _previousRank = null;
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
    _showRankUpDialog = false;
    _previousRank = null;
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
  Future<void> fetchLevelFull() async {
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await _apiClient.get('/users/me/level-full');
      final bool isFirstLoad = _rawLevelFull.isEmpty;

      _rawLevelFull = data;
      _numericLevel = data['numeric_level'] ?? 1;
      _currentXpInLevel = data['current_xp_in_level'] ?? 0;
      _xpForNextLevel = data['xp_for_next_level'] ?? 100;
      _levelProgressPercent = (data['level_progress_percent'] ?? 0).toDouble();
      _totalXp = data['total_xp'] ?? 0;
      _proficiencyLevel =
          data['cefr_level'] ?? data['proficiency_level'] ?? 'A1';
      _proficiencyName =
          data['cefr_name'] ?? data['proficiency_name'] ?? 'Beginner';

      final oldRank = _rank;
      final newRank = data['rank'] ?? 'bronze';
      
      // Rank thresholds usually go: bronze -> silver -> gold -> platinum -> diamond -> master -> grandmaster.
      // Easiest is to check just if it's different and oldRank is not initial state (unless we just started).
      // Or we can just trust if oldRank != newRank and we already had a valid rank.
      // But wait: What if oldRank is 'bronze' from reset() but the user was actually 'gold' on first load?
      // If we show rank up, we only want to show it if we PREVIOUSLY fetched their rank successfully and NOW it changed.
      // How do we know it's a "first load"? `_rawLevelFull.isEmpty` tells us if it's the first fetch.
      
      _rank = newRank;
      _rankName = data['rank_name'] ?? 'Bronze';
      _rankScore = (data['rank_score'] ?? 0).toDouble();

      // Check for rank change. If not first load, and oldRank != newRank, show popup
      if (!isFirstLoad && oldRank != newRank && oldRank.isNotEmpty) {
        // Technically this could trigger on rank down too, but LexiLingo rank scores only go up right now.
        _showRankUpDialog = true;
        _previousRank = oldRank;
        debugPrint('Rank up! $oldRank -> $newRank');
      }

      // Keep CEFR LevelStatus in sync for legacy display (no extra notifyListeners).
      _levelStatus = LevelCalculator.calculateLevelStatus(_totalXp);
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
