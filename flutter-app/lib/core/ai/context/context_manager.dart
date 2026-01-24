import '../models/ai_task.dart';

/// Manages conversation context, learner profile, and embeddings
/// Following the architecture: Context Encoder + Redis Cache + Knowledge Graph
class ContextManager {
  // Conversation history buffer (last 5 turns)
  final List<ConversationTurn> _history = [];
  static const int _maxHistorySize = 5;

  // Learner profile
  LearnerProfile? _learnerProfile;

  // TODO: Integrate with Redis for caching
  // TODO: Integrate with sentence-transformers (all-MiniLM-L6-v2) for embeddings
  // TODO: Integrate with Knowledge Graph (NetworkX / KuzuDB)

  /// Add a new conversation turn to history
  void addTurn(ConversationTurn turn) {
    _history.add(turn);
    if (_history.length > _maxHistorySize) {
      _history.removeAt(0); // Remove oldest turn
    }
  }

  /// Get conversation history
  List<ConversationTurn> get history => List.unmodifiable(_history);

  /// Set learner profile
  void setLearnerProfile(LearnerProfile profile) {
    _learnerProfile = profile;
  }

  /// Get learner profile
  LearnerProfile? get learnerProfile => _learnerProfile;

  /// Get learner level (default to A2 if not set)
  LearnerLevel get learnerLevel =>
      _learnerProfile?.level ?? LearnerLevel.a2;

  /// Get context summary for AI prompt
  String getContextSummary() {
    if (_history.isEmpty) {
      return 'This is the start of a new conversation.';
    }

    final buffer = StringBuffer();
    buffer.writeln('Recent conversation:');
    for (var turn in _history) {
      buffer.writeln('User: ${turn.userMessage}');
      if (turn.aiResponse != null) {
        buffer.writeln('AI: ${turn.aiResponse}');
      }
    }

    if (_learnerProfile != null) {
      buffer.writeln('\nLearner profile:');
      buffer.writeln('Level: ${_learnerProfile!.level.displayName}');
      if (_learnerProfile!.commonErrors.isNotEmpty) {
        buffer.writeln(
            'Common errors: ${_learnerProfile!.commonErrors.join(", ")}');
      }
    }

    return buffer.toString();
  }

  /// Check if learner needs Vietnamese explanation
  /// Returns true if level is A2 or has low confidence
  bool needsVietnameseExplanation({double? confidenceScore}) {
    if (_learnerProfile?.level == LearnerLevel.a2) {
      return true;
    }

    if (confidenceScore != null && confidenceScore < 0.8) {
      return true;
    }

    return false;
  }

  /// Clear conversation history
  void clearHistory() {
    _history.clear();
  }

  /// Get embedding for text (placeholder - TODO: integrate with all-MiniLM-L6-v2)
  Future<List<double>> getEmbedding(String text) async {
    // TODO: Implement actual embedding generation
    // For now, return a placeholder vector
    return List.filled(384, 0.0); // 384-dim for all-MiniLM-L6-v2
  }

  /// Query knowledge graph for related concepts (placeholder)
  Future<List<String>> queryKnowledgeGraph(String concept) async {
    // TODO: Implement knowledge graph query
    // This should use NetworkX or KuzuDB to find related concepts
    return [];
  }
}

/// Represents a conversation turn (user message + AI response)
class ConversationTurn {
  final String userMessage;
  final String? aiResponse;
  final DateTime timestamp;

  ConversationTurn({
    required this.userMessage,
    this.aiResponse,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Learner profile stored in Redis
class LearnerProfile {
  final String userId;
  final LearnerLevel level;
  final List<String> commonErrors;
  final int totalSessions;
  final DateTime lastActive;

  LearnerProfile({
    required this.userId,
    required this.level,
    required this.commonErrors,
    required this.totalSessions,
    DateTime? lastActive,
  }) : lastActive = lastActive ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'level': level.displayName,
      'common_errors': commonErrors,
      'total_sessions': totalSessions,
      'last_active': lastActive.toIso8601String(),
    };
  }

  factory LearnerProfile.fromJson(Map<String, dynamic> json) {
    return LearnerProfile(
      userId: json['user_id'],
      level: LearnerLevel.values.firstWhere(
        (e) => e.displayName == json['level'],
        orElse: () => LearnerLevel.a2,
      ),
      commonErrors: List<String>.from(json['common_errors'] ?? []),
      totalSessions: json['total_sessions'] ?? 0,
      lastActive: DateTime.parse(json['last_active']),
    );
  }
}
