import 'package:flutter/foundation.dart';

import '../../data/models/story_model.dart';
import '../../data/models/topic_session_model.dart';
import '../../domain/repositories/story_repository.dart';

/// State management for Story/Topic-based conversation
class StoryProvider extends ChangeNotifier {
  final StoryRepository repository;

  StoryProvider({required this.repository});

  // Stories state
  List<StoryListItem> _stories = [];
  List<String> _categories = [];
  Story? _currentStoryDetails;
  bool _isLoading = false;
  String? _error;

  // Filters
  String? _filterCategory;
  DifficultyLevel? _filterDifficulty;

  // Topic session state
  TopicSession? _currentSession;
  List<TopicChatMessage> _messages = [];
  bool _isSendingMessage = false;
  String? _sessionError;

  // Getters
  List<StoryListItem> get stories => _stories;
  List<String> get categories => _categories;
  Story? get currentStoryDetails => _currentStoryDetails;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get filterCategory => _filterCategory;
  DifficultyLevel? get filterDifficulty => _filterDifficulty;
  TopicSession? get currentSession => _currentSession;
  List<TopicChatMessage> get messages => _messages;
  bool get isSendingMessage => _isSendingMessage;
  String? get sessionError => _sessionError;
  bool get hasActiveSession => _currentSession != null;

  /// Get filtered stories based on current filters
  List<StoryListItem> get filteredStories {
    var result = _stories;

    if (_filterCategory != null) {
      result = result.where((s) => s.category == _filterCategory).toList();
    }

    if (_filterDifficulty != null) {
      result = result.where((s) => s.difficultyLevel == _filterDifficulty).toList();
    }

    return result;
  }

  /// Load all stories
  Future<void> loadStories({
    String? category,
    DifficultyLevel? difficultyLevel,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await repository.getStories(
      category: category,
      difficultyLevel: difficultyLevel,
    );

    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (stories) {
        _stories = stories;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Load categories
  Future<void> loadCategories() async {
    final result = await repository.getCategories();
    result.fold(
      (failure) => debugPrint('Failed to load categories: ${failure.message}'),
      (categories) {
        _categories = categories;
        notifyListeners();
      },
    );
  }

  /// Set filter
  void setFilter({String? category, DifficultyLevel? difficultyLevel}) {
    _filterCategory = category;
    _filterDifficulty = difficultyLevel;
    notifyListeners();
  }

  /// Clear filters
  void clearFilters() {
    _filterCategory = null;
    _filterDifficulty = null;
    notifyListeners();
  }

  /// Load story details
  Future<void> loadStoryDetails(String storyId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await repository.getStoryDetails(storyId);

    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (story) {
        _currentStoryDetails = story;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// Start a new topic session
  Future<bool> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'qwen',
  }) async {
    _isLoading = true;
    _sessionError = null;
    notifyListeners();

    final result = await repository.startTopicSession(
      userId: userId,
      storyId: storyId,
      sessionTitle: sessionTitle,
      preferredLlm: preferredLlm,
    );

    return result.fold(
      (failure) {
        _sessionError = failure.message;
        _isLoading = false;
        notifyListeners();
        return false;
      },
      (session) {
        _currentSession = session;
        _messages = [
          // Add opening message as AI message
          TopicChatMessage(
            id: 'opening_${session.sessionId}',
            sessionId: session.sessionId,
            content: session.openingMessage,
            isUser: false,
            timestamp: session.createdAt,
          ),
        ];
        _isLoading = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Send a message in the topic session
  Future<bool> sendMessage({
    required String userId,
    required String message,
  }) async {
    if (_currentSession == null) {
      _sessionError = 'No active session';
      notifyListeners();
      return false;
    }

    _isSendingMessage = true;
    _sessionError = null;
    notifyListeners();

    // Add user message immediately
    final userMessage = TopicChatMessage(
      id: 'user_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: _currentSession!.sessionId,
      content: message,
      isUser: true,
      timestamp: DateTime.now(),
    );
    _messages.add(userMessage);
    notifyListeners();

    final result = await repository.sendTopicMessage(
      sessionId: _currentSession!.sessionId,
      userId: userId,
      message: message,
    );

    return result.fold(
      (failure) {
        _sessionError = failure.message;
        _isSendingMessage = false;
        notifyListeners();
        return false;
      },
      (response) {
        // Add AI response
        final aiMessage = TopicChatMessage(
          id: response.messageId,
          sessionId: _currentSession!.sessionId,
          content: response.response,
          isUser: false,
          timestamp: DateTime.now(),
          hints: response.educationalHints,
          llmMetadata: response.llmMetadata,
        );
        _messages.add(aiMessage);
        _isSendingMessage = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Load existing session messages
  Future<void> loadSessionMessages(String sessionId) async {
    _isLoading = true;
    _sessionError = null;
    notifyListeners();

    final result = await repository.getTopicMessages(sessionId);

    result.fold(
      (failure) {
        _sessionError = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (messages) {
        _messages = messages;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  /// End the current session
  void endSession() {
    _currentSession = null;
    _messages = [];
    _currentStoryDetails = null;
    _sessionError = null;
    notifyListeners();
  }

  /// Check LLM health
  Future<Map<String, dynamic>?> checkLlmHealth() async {
    final result = await repository.checkLlmHealth();
    return result.fold(
      (failure) => null,
      (health) => health,
    );
  }
}
