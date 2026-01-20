/// Task types that the AI Orchestrator can handle
enum AITaskType {
  /// Grammar correction and analysis
  grammar,
  
  /// Fluency assessment
  fluency,
  
  /// Vocabulary level analysis
  vocabulary,
  
  /// Dialogue/conversation practice
  dialogue,
  
  /// Pronunciation analysis (requires audio)
  pronunciation,
  
  /// Vietnamese explanation (for A2 learners)
  vietnameseExplanation,
}

/// Complexity level of the user's input
enum TaskComplexity {
  simple,
  medium,
  complex,
}

/// CEFR levels for learner proficiency
enum LearnerLevel {
  a2,
  b1,
  b2,
}

extension LearnerLevelExtension on LearnerLevel {
  String get displayName {
    switch (this) {
      case LearnerLevel.a2:
        return 'A2';
      case LearnerLevel.b1:
        return 'B1';
      case LearnerLevel.b2:
        return 'B2';
    }
  }
}

/// Feedback strategy based on learner level and errors
enum FeedbackStrategy {
  /// No errors, just praise
  praise,
  
  /// 1-2 errors, gentle correction
  correct,
  
  /// 3+ errors, detailed explanation
  explain,
  
  /// Repeated same error, focused drill
  drill,
}

/// Result of task analysis
class TaskAnalysis {
  final List<AITaskType> primaryTasks;
  final List<AITaskType> parallelTasks;
  final bool needVietnamese;
  final FeedbackStrategy strategy;
  final TaskComplexity complexity;
  final LearnerLevel learnerLevel;

  const TaskAnalysis({
    required this.primaryTasks,
    required this.parallelTasks,
    required this.needVietnamese,
    required this.strategy,
    required this.complexity,
    required this.learnerLevel,
  });

  @override
  String toString() {
    return 'TaskAnalysis(primary: $primaryTasks, parallel: $parallelTasks, '
        'needVI: $needVietnamese, strategy: $strategy, '
        'complexity: $complexity, level: $learnerLevel)';
  }
}
