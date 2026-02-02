import 'package:equatable/equatable.dart';

/// Skill types for proficiency assessment
enum SkillType {
  vocabulary,
  grammar,
  reading,
  listening,
  speaking,
  writing,
}

extension SkillTypeExtension on SkillType {
  String get displayName {
    switch (this) {
      case SkillType.vocabulary:
        return 'Vocabulary';
      case SkillType.grammar:
        return 'Grammar';
      case SkillType.reading:
        return 'Reading';
      case SkillType.listening:
        return 'Listening';
      case SkillType.speaking:
        return 'Speaking';
      case SkillType.writing:
        return 'Writing';
    }
  }

  String get icon {
    switch (this) {
      case SkillType.vocabulary:
        return '📚';
      case SkillType.grammar:
        return '✏️';
      case SkillType.reading:
        return '📖';
      case SkillType.listening:
        return '🎧';
      case SkillType.speaking:
        return '🎤';
      case SkillType.writing:
        return '✍️';
    }
  }
}

/// Individual skill score
class SkillScore extends Equatable {
  final SkillType skill;
  final double score;
  final double confidence;
  final String estimatedLevel;
  final double accuracy;
  final String trend;
  final int exercisesCompleted;

  const SkillScore({
    required this.skill,
    required this.score,
    required this.confidence,
    required this.estimatedLevel,
    required this.accuracy,
    required this.trend,
    required this.exercisesCompleted,
  });

  factory SkillScore.fromJson(SkillType skill, Map<String, dynamic> json) {
    return SkillScore(
      skill: skill,
      score: (json['score'] ?? 0).toDouble(),
      confidence: (json['confidence'] ?? 0).toDouble(),
      estimatedLevel: json['estimated_level'] ?? 'A1',
      accuracy: (json['accuracy'] ?? 0).toDouble(),
      trend: json['trend'] ?? 'stable',
      exercisesCompleted: json['exercises_completed'] ?? 0,
    );
  }

  bool get isImproving => trend == 'improving';
  bool get isDeclining => trend == 'declining';

  @override
  List<Object?> get props => [skill, score, confidence, estimatedLevel, accuracy, trend, exercisesCompleted];
}

/// Requirement status for level progression
class LevelRequirement extends Equatable {
  final String name;
  final String required;
  final String current;
  final bool met;
  final double progress;

  const LevelRequirement({
    required this.name,
    required this.required,
    required this.current,
    required this.met,
    required this.progress,
  });

  factory LevelRequirement.fromJson(String name, Map<String, dynamic> json) {
    return LevelRequirement(
      name: name,
      required: json['required']?.toString() ?? '0',
      current: json['current']?.toString() ?? '0',
      met: json['met'] ?? false,
      progress: (json['progress'] ?? 0).toDouble(),
    );
  }

  @override
  List<Object?> get props => [name, required, current, met, progress];
}

/// Next level progression info
class NextLevelInfo extends Equatable {
  final String? level;
  final double progress;
  final bool qualifies;
  final Map<String, LevelRequirement> requirements;
  final List<String> blockers;

  const NextLevelInfo({
    this.level,
    required this.progress,
    required this.qualifies,
    required this.requirements,
    required this.blockers,
  });

  factory NextLevelInfo.fromJson(Map<String, dynamic> json) {
    final requirementsJson = json['requirements'] as Map<String, dynamic>? ?? {};
    final requirements = <String, LevelRequirement>{};
    
    requirementsJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        requirements[key] = LevelRequirement.fromJson(key, value);
      }
    });

    return NextLevelInfo(
      level: json['level'],
      progress: (json['progress'] ?? 0).toDouble(),
      qualifies: json['qualifies'] ?? false,
      requirements: requirements,
      blockers: List<String>.from(json['blockers'] ?? []),
    );
  }

  int get requirementsMet => requirements.values.where((r) => r.met).length;
  int get totalRequirements => requirements.length;

  @override
  List<Object?> get props => [level, progress, qualifies, requirements, blockers];
}

/// User's proficiency profile - comprehensive language assessment
class ProficiencyProfile extends Equatable {
  final String userId;
  final String assessedLevel;
  final double overallScore;
  final int totalXp;
  final Map<SkillType, SkillScore> skills;
  final int exercisesCompleted;
  final int correctExercises;
  final double accuracy;
  final int lessonsCompleted;
  final NextLevelInfo? nextLevel;
  final DateTime? lastAssessment;

  const ProficiencyProfile({
    required this.userId,
    required this.assessedLevel,
    required this.overallScore,
    required this.totalXp,
    required this.skills,
    required this.exercisesCompleted,
    required this.correctExercises,
    required this.accuracy,
    required this.lessonsCompleted,
    this.nextLevel,
    this.lastAssessment,
  });

  factory ProficiencyProfile.empty() {
    return const ProficiencyProfile(
      userId: '',
      assessedLevel: 'A1',
      overallScore: 0,
      totalXp: 0,
      skills: {},
      exercisesCompleted: 0,
      correctExercises: 0,
      accuracy: 0,
      lessonsCompleted: 0,
    );
  }

  factory ProficiencyProfile.fromJson(Map<String, dynamic> json) {
    final skillsJson = json['skills'] as Map<String, dynamic>? ?? {};
    final skills = <SkillType, SkillScore>{};

    skillsJson.forEach((key, value) {
      try {
        final skillType = SkillType.values.firstWhere(
          (s) => s.name == key,
          orElse: () => SkillType.vocabulary,
        );
        if (value is Map<String, dynamic>) {
          skills[skillType] = SkillScore.fromJson(skillType, value);
        }
      } catch (_) {}
    });

    final stats = json['statistics'] as Map<String, dynamic>? ?? {};
    final nextLevelJson = json['next_level'] as Map<String, dynamic>?;

    return ProficiencyProfile(
      userId: json['user_id'] ?? '',
      assessedLevel: json['assessed_level'] ?? 'A1',
      overallScore: (json['overall_score'] ?? 0).toDouble(),
      totalXp: json['total_xp'] ?? 0,
      skills: skills,
      exercisesCompleted: stats['exercises_completed'] ?? 0,
      correctExercises: stats['correct_exercises'] ?? 0,
      accuracy: (stats['accuracy'] ?? 0).toDouble(),
      lessonsCompleted: stats['lessons_completed'] ?? 0,
      nextLevel: nextLevelJson != null ? NextLevelInfo.fromJson(nextLevelJson) : null,
      lastAssessment: json['last_assessment'] != null 
          ? DateTime.tryParse(json['last_assessment']) 
          : null,
    );
  }

  /// Get the weakest skills that need improvement
  List<SkillScore> get weakestSkills {
    final sortedSkills = skills.values.toList()
      ..sort((a, b) => a.score.compareTo(b.score));
    return sortedSkills.take(2).toList();
  }

  /// Get the strongest skills
  List<SkillScore> get strongestSkills {
    final sortedSkills = skills.values.toList()
      ..sort((a, b) => b.score.compareTo(a.score));
    return sortedSkills.take(2).toList();
  }

  /// Check if user is close to leveling up
  bool get isCloseToLevelUp => (nextLevel?.progress ?? 0) >= 80;

  @override
  List<Object?> get props => [
    userId,
    assessedLevel,
    overallScore,
    totalXp,
    skills,
    exercisesCompleted,
    correctExercises,
    accuracy,
    lessonsCompleted,
    nextLevel,
    lastAssessment,
  ];
}

/// Result from recording exercises
class ExerciseRecordResult extends Equatable {
  final int exercisesRecorded;
  final Map<String, dynamic> skillUpdates;
  final bool levelChanged;
  final String previousLevel;
  final String currentLevel;
  final double progressToNext;
  final int xpEarned;
  final int totalXp;
  final String message;

  const ExerciseRecordResult({
    required this.exercisesRecorded,
    required this.skillUpdates,
    required this.levelChanged,
    required this.previousLevel,
    required this.currentLevel,
    required this.progressToNext,
    required this.xpEarned,
    required this.totalXp,
    required this.message,
  });

  factory ExerciseRecordResult.fromJson(Map<String, dynamic> json) {
    return ExerciseRecordResult(
      exercisesRecorded: json['exercises_recorded'] ?? 0,
      skillUpdates: json['skill_updates'] ?? {},
      levelChanged: json['level_changed'] ?? false,
      previousLevel: json['previous_level'] ?? 'A1',
      currentLevel: json['current_level'] ?? 'A1',
      progressToNext: (json['progress_to_next'] ?? 0).toDouble(),
      xpEarned: json['xp_earned'] ?? 0,
      totalXp: json['total_xp'] ?? 0,
      message: json['message'] ?? '',
    );
  }

  @override
  List<Object?> get props => [
    exercisesRecorded,
    skillUpdates,
    levelChanged,
    previousLevel,
    currentLevel,
    progressToNext,
    xpEarned,
    totalXp,
    message,
  ];
}
