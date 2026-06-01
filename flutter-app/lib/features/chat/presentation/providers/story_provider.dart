import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../data/models/story_model.dart';
import '../../data/models/topic_session_model.dart';
import '../../domain/repositories/story_repository.dart';

/// State management for Story/Topic-based conversation
class StoryProvider extends ChangeNotifier {
  final StoryRepository repository;
  static const String _recentTopicsKey = 'recent_topic_ids';
  static const String _topicSessionPrefix = 'topic_session_';

  StoryProvider({required this.repository}) {
    _loadRecentlyUsed();
  }

  // Stories state
  List<StoryListItem> _stories = [];
  List<StoryListItem> _recentlyUsed = [];
  List<String> _categories = [];
  Story? _currentStoryDetails;
  bool _isLoading = false;
  bool _isWarming = false;
  String? _error;

  // Filters
  String? _filterCategory;
  DifficultyLevel? _filterDifficulty;

  // Topic session state
  TopicSession? _currentSession;
  List<TopicChatMessage> _messages = [];
  bool _isSendingMessage = false;
  bool _isLoadingMoreMessages = false;
  bool _hasMoreMessages = true;
  String? _nextMessageCursor;
  final int _messagesPageSize = 20;
  String? _sessionError;

  // Getters
  List<StoryListItem> get stories => _stories;
  List<StoryListItem> get recentlyUsed => _recentlyUsed;
  List<String> get categories => _categories;
  Story? get currentStoryDetails => _currentStoryDetails;
  bool get isLoading => _isLoading;
  bool get isWarming => _isWarming;
  String? get error => _error;
  String? get filterCategory => _filterCategory;
  DifficultyLevel? get filterDifficulty => _filterDifficulty;
  TopicSession? get currentSession => _currentSession;
  List<TopicChatMessage> get messages => _messages;
  bool get isSendingMessage => _isSendingMessage;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreMessages => _hasMoreMessages;
  String? get sessionError => _sessionError;
  bool get hasActiveSession => _currentSession != null;

  /// Get filtered stories based on current filters
  List<StoryListItem> get filteredStories {
    var result = _stories;

    if (_filterCategory != null) {
      result = result.where((s) => s.category == _filterCategory).toList();
    }

    if (_filterDifficulty != null) {
      result = result
          .where((s) => s.difficultyLevel == _filterDifficulty)
          .toList();
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

        // Sync full story data for recently used if needed
        _syncRecentlyUsedWithStories();

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

  /// Warm topic cache
  Future<bool> warmTopicCache({
    required String storyId,
    required String userId,
  }) async {
    _isWarming = true;
    _error = null;
    notifyListeners();

    final result = await repository.warmTopicCache(
      storyId: storyId,
      userId: userId,
    );

    return result.fold(
      (failure) {
        _error = failure.message;
        _isWarming = false;
        notifyListeners();
        return false;
      },
      (success) {
        _isWarming = false;
        notifyListeners();
        return true;
      },
    );
  }

  /// Pre-warm top 3 recently used topics
  Future<void> preWarmRecents(String userId) async {
    if (_recentlyUsed.isEmpty) return;

    final toWarm = _recentlyUsed.take(3).toList();
    for (var story in toWarm) {
      // Best effort warming, don't block or show loading
      repository.warmTopicCache(storyId: story.storyId, userId: userId);
    }
  }

  /// Start a new topic session
  Future<bool> startTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'tracecag',
  }) async {
    // Clear previous session state
    clearActiveSession();

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

        // Add to recently used
        final story = _stories.firstWhere(
          (s) => s.storyId == storyId,
          orElse: () => session.story,
        );
        _addToRecentlyUsed(story);

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
        _hasMoreMessages = false;
        _nextMessageCursor = null;
        _isLoadingMoreMessages = false;
        _isLoading = false;
        _saveTopicSession(storyId, session);
        notifyListeners();
        return true;
      },
    );
  }

  /// Restore an existing topic session for [storyId], or start a new one.
  ///
  /// On success the provider state is ready for the chat page.
  Future<bool> restoreOrStartTopicSession({
    required String userId,
    required String storyId,
    String? sessionTitle,
    String preferredLlm = 'tracecag',
  }) async {
    final saved = await _loadSavedTopicSession(storyId);

    if (saved != null) {
      _isLoading = true;
      _sessionError = null;
      notifyListeners();

      final result = await repository.getTopicMessagesPaged(
        saved.sessionId,
        limit: _messagesPageSize,
      );

      final restored = result.fold((_) => false, (page) {
        _currentSession = saved;
        _messages = page.messages.isNotEmpty
            ? page.messages
            : [
                TopicChatMessage(
                  id: 'opening_${saved.sessionId}',
                  sessionId: saved.sessionId,
                  content: saved.openingMessage,
                  isUser: false,
                  timestamp: saved.createdAt,
                ),
              ];
        _hasMoreMessages = page.hasMore;
        _nextMessageCursor = page.nextCursor;
        _isLoadingMoreMessages = false;
        _isLoading = false;
        notifyListeners();
        return true;
      });

      if (restored) return true;

      // Session expired or not found — discard stale cache
      _isLoading = false;
      _clearSavedTopicSession(storyId);
      notifyListeners();
    }

    return startTopicSession(
      userId: userId,
      storyId: storyId,
      sessionTitle: sessionTitle,
      preferredLlm: preferredLlm,
    );
  }

  /// Clear the active topic session
  void clearActiveSession() {
    _currentSession = null;
    _messages = [];
    _isLoadingMoreMessages = false;
    _hasMoreMessages = true;
    _nextMessageCursor = null;
    _sessionError = null;
    notifyListeners();
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

    final result = await repository.getTopicMessagesPaged(
      sessionId,
      limit: _messagesPageSize,
    );

    result.fold(
      (failure) {
        // Fallback to legacy full-history endpoint.
        repository.getTopicMessages(sessionId).then((legacy) {
          legacy.fold(
            (legacyFailure) {
              _sessionError = legacyFailure.message;
              _isLoading = false;
              notifyListeners();
            },
            (messages) {
              _messages = messages;
              _hasMoreMessages = false;
              _nextMessageCursor = null;
              _isLoading = false;
              notifyListeners();
            },
          );
        });
      },
      (page) {
        _messages = page.messages;
        _hasMoreMessages = page.hasMore;
        _nextMessageCursor = page.nextCursor;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> loadOlderMessages() async {
    if (_currentSession == null ||
        _isLoadingMoreMessages ||
        !_hasMoreMessages) {
      return;
    }

    _isLoadingMoreMessages = true;
    notifyListeners();

    final result = await repository.getTopicMessagesPaged(
      _currentSession!.sessionId,
      limit: _messagesPageSize,
      cursor: _nextMessageCursor,
    );

    result.fold(
      (failure) {
        _sessionError = failure.message;
        _isLoadingMoreMessages = false;
        notifyListeners();
      },
      (page) {
        if (page.messages.isNotEmpty) {
          _messages.insertAll(0, page.messages);
        }
        _hasMoreMessages = page.hasMore;
        _nextMessageCursor = page.nextCursor;
        _isLoadingMoreMessages = false;
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

  void _addToRecentlyUsed(StoryListItem story) {
    _recentlyUsed.removeWhere((s) => s.storyId == story.storyId);
    _recentlyUsed.insert(0, story);
    if (_recentlyUsed.length > 5) {
      _recentlyUsed = _recentlyUsed.sublist(0, 5);
    }
    _saveRecentlyUsed();
    notifyListeners();
  }

  /// Check LLM health
  Future<Map<String, dynamic>?> checkLlmHealth() async {
    final result = await repository.checkLlmHealth();
    return result.fold((failure) => null, (health) => health);
  }

  Future<void> _saveTopicSession(String storyId, TopicSession session) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_topicSessionPrefix$storyId',
        jsonEncode(session.toJson()),
      );
    } catch (e) {
      debugPrint('Error saving topic session: $e');
    }
  }

  Future<TopicSession?> _loadSavedTopicSession(String storyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_topicSessionPrefix$storyId');
      if (raw == null) return null;
      return TopicSession.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (e) {
      debugPrint('Error loading saved topic session: $e');
      return null;
    }
  }

  Future<void> _clearSavedTopicSession(String storyId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_topicSessionPrefix$storyId');
    } catch (e) {
      debugPrint('Error clearing saved topic session: $e');
    }
  }

  Future<void> _saveRecentlyUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final ids = _recentlyUsed.map((s) => s.storyId).toList();
      await prefs.setStringList(_recentTopicsKey, ids);

      // Also cache full JSON for quick boot
      final jsonList = _recentlyUsed
          .map((s) => jsonEncode(s.toJson()))
          .toList();
      await prefs.setStringList('${_recentTopicsKey}_data', jsonList);
    } catch (e) {
      debugPrint('Error saving recent topics: $e');
    }
  }

  Future<void> _loadRecentlyUsed() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = prefs.getStringList('${_recentTopicsKey}_data');

      if (jsonList != null) {
        _recentlyUsed = jsonList
            .map((s) => StoryListItem.fromJson(jsonDecode(s)))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading recent topics: $e');
    }
  }

  void _syncRecentlyUsedWithStories() {
    if (_recentlyUsed.isEmpty || _stories.isEmpty) return;

    for (int i = 0; i < _recentlyUsed.length; i++) {
      try {
        final fullStory = _stories.firstWhere(
          (s) => s.storyId == _recentlyUsed[i].storyId,
        );
        _recentlyUsed[i] = fullStory;
      } catch (_) {
        // Keep existing if not found in current list
      }
    }
  }
}
