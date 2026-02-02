import 'package:flutter/foundation.dart';
import '../../domain/entities/proficiency_entity.dart';
import '../../data/datasources/proficiency_data_source.dart';

/// Proficiency Provider
/// 
/// Manages user proficiency state with multi-dimensional skill assessment.
/// This replaces simple XP-based leveling with a comprehensive evaluation
/// of vocabulary, grammar, reading, listening, speaking, and writing skills.
/// 
/// Key difference from XP-based system:
/// - XP is for gamification (rewards, leaderboards)
/// - Proficiency level is based on actual skill demonstration
/// 
/// Users cannot "grind" their way to C2 just by doing easy exercises.
/// They must demonstrate competency in multiple skill areas to advance.
class ProficiencyProvider with ChangeNotifier {
  final ProficiencyDataSource? _dataSource;
  
  ProficiencyProfile _profile = ProficiencyProfile.empty();
  bool _isLoading = false;
  String? _errorMessage;
  bool _showLevelUpDialog = false;
  String? _previousLevel;
  
  ProficiencyProvider({ProficiencyDataSource? dataSource}) 
      : _dataSource = dataSource;

  // Getters
  ProficiencyProfile get profile => _profile;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get showLevelUpDialog => _showLevelUpDialog;
  String? get previousLevel => _previousLevel;

  // Convenience getters
  String get assessedLevel => _profile.assessedLevel;
  double get overallScore => _profile.overallScore;
  int get totalXp => _profile.totalXp;
  Map<SkillType, SkillScore> get skills => _profile.skills;
  NextLevelInfo? get nextLevel => _profile.nextLevel;
  double get progressToNextLevel => nextLevel?.progress ?? 0;
  bool get isCloseToLevelUp => _profile.isCloseToLevelUp;
  List<SkillScore> get weakestSkills => _profile.weakestSkills;
  List<SkillScore> get strongestSkills => _profile.strongestSkills;
  
  /// Level code for display (A1, A2, B1, B2, C1, C2)
  String get levelCode => _profile.assessedLevel;
  
  /// Human-readable level name
  String get levelName {
    switch (_profile.assessedLevel) {
      case 'A1': return 'Beginner';
      case 'A2': return 'Elementary';
      case 'B1': return 'Intermediate';
      case 'B2': return 'Upper Intermediate';
      case 'C1': return 'Advanced';
      case 'C2': return 'Mastery';
      default: return 'Beginner';
    }
  }
  
  /// Full display name (e.g., "B2 Upper Intermediate")
  String get displayName => '$levelCode $levelName';

  /// Load user's proficiency profile from API
  Future<void> loadProfile() async {
    final dataSource = _dataSource;
    if (dataSource == null) return;
    
    _isLoading = true;
    _errorMessage = null;
    notifyListeners();

    try {
      _profile = await dataSource.getProfile();
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _isLoading = false;
      _errorMessage = 'Failed to load proficiency profile: $e';
      notifyListeners();
      debugPrint('Error loading proficiency: $e');
    }
  }

  /// Record exercise results and update proficiency
  /// 
  /// Call this after completing exercises to:
  /// 1. Track performance in specific skills
  /// 2. Update skill scores
  /// 3. Check for level changes
  /// 4. Award XP (gamification separate from proficiency)
  Future<ExerciseRecordResult?> recordExercises(
    List<ExerciseResultData> results,
  ) async {
    final dataSource = _dataSource;
    if (dataSource == null || results.isEmpty) return null;

    try {
      final jsonResults = results.map((r) => r.toJson()).toList();
      final result = await dataSource.recordExercises(jsonResults);
      
      // Check for level change
      if (result.levelChanged) {
        _previousLevel = result.previousLevel;
        _showLevelUpDialog = true;
        debugPrint('Level up! ${result.previousLevel} -> ${result.currentLevel}');
      }
      
      // Reload profile to get updated data
      await loadProfile();
      
      return result;
    } catch (e) {
      _errorMessage = 'Failed to record exercises: $e';
      notifyListeners();
      debugPrint('Error recording exercises: $e');
      return null;
    }
  }

  /// Get detailed requirements check for next level
  Future<Map<String, dynamic>?> checkLevelRequirements() async {
    final dataSource = _dataSource;
    if (dataSource == null) return null;

    try {
      return await dataSource.checkLevelRequirements();
    } catch (e) {
      debugPrint('Error checking level requirements: $e');
      return null;
    }
  }

  /// Dismiss the level up dialog
  void dismissLevelUpDialog() {
    _showLevelUpDialog = false;
    _previousLevel = null;
    notifyListeners();
  }

  /// Get skill score by type
  SkillScore? getSkillScore(SkillType skill) {
    return _profile.skills[skill];
  }

  /// Get skill progress percentage (0-100)
  double getSkillProgress(SkillType skill) {
    return _profile.skills[skill]?.score ?? 0;
  }

  /// Get blockers preventing level up
  List<String> get levelUpBlockers => nextLevel?.blockers ?? [];

  /// Get requirements met count for next level
  String get requirementsProgress {
    if (nextLevel == null) return 'Max level reached';
    return '${nextLevel!.requirementsMet}/${nextLevel!.totalRequirements} requirements met';
  }

  /// Get recommendation message
  String get improvementRecommendation {
    if (weakestSkills.isEmpty) {
      return 'Complete more exercises to get personalized recommendations.';
    }
    
    final weakest = weakestSkills.first;
    return 'Focus on improving your ${weakest.skill.displayName} skills to reach the next level.';
  }

  /// Check if user qualifies for next level
  bool get qualifiesForNextLevel => nextLevel?.qualifies ?? false;

  /// Reset provider state
  void reset() {
    _profile = ProficiencyProfile.empty();
    _isLoading = false;
    _errorMessage = null;
    _showLevelUpDialog = false;
    _previousLevel = null;
    notifyListeners();
  }
}

/// Data class for exercise results to be recorded
class ExerciseResultData {
  final String exerciseType;
  final SkillType skill;
  final String difficultyLevel;
  final bool isCorrect;
  final double score;
  final int timeSpentSeconds;
  final String? lessonId;
  final String? courseId;

  ExerciseResultData({
    required this.exerciseType,
    required this.skill,
    required this.difficultyLevel,
    required this.isCorrect,
    required this.score,
    this.timeSpentSeconds = 0,
    this.lessonId,
    this.courseId,
  });

  Map<String, dynamic> toJson() => {
    'exercise_type': exerciseType,
    'skill': skill.name,
    'difficulty_level': difficultyLevel,
    'is_correct': isCorrect,
    'score': score,
    'time_spent_seconds': timeSpentSeconds,
    if (lessonId != null) 'lesson_id': lessonId,
    if (courseId != null) 'course_id': courseId,
  };
}
