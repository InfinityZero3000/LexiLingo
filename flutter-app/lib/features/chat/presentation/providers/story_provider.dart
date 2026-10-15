import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../../domain/entities/story.dart';
import '../../domain/entities/topic_session.dart';
import '../../domain/entities/topic_stream_event.dart';
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
  int _mistakesSavedThisSession = 0;
  int _wordsSavedThisSession = 0;

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
  int get mistakesSavedThisSession => _mistakesSavedThisSession;
  int get wordsSavedThisSession => _wordsSavedThisSession;

  /// Called when the learner saves a correction card into the Mistake
  /// Notebook — tracked so the end-of-session summary can show it.
  void recordMistakeSaved() {
    _mistakesSavedThisSession++;
    notifyListeners();
  }

  /// Called when the learner saves a vocabulary hint card as a new word.
  void recordWordSaved() {
    _wordsSavedThisSession++;
    notifyListeners();
  }

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
        _mistakesSavedThisSession = 0;
        _wordsSavedThisSession = 0;
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
    _mistakesSavedThisSession = 0;
    _wordsSavedThisSession = 0;
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

  /// Streaming variant of [sendMessage] — same TraceCAG pipeline and 2-tier
  /// fallback server-side, delivered as SSE so the AI bubble fills in
  /// word-by-word instead of popping in all at once. [sendMessage] itself
  /// is left untouched as a manual fallback path.
  ///
  /// Mirrors LexiChatProvider.sendMessageStreaming's recovery behavior: a
  /// [TopicStreamError] event or a stream that closes before any content
  /// arrived is safe to silently retry via the non-streaming [sendMessage],
  /// because the backend only emits those before it persists anything for
  /// the turn. A stream that closes mid-typing (partial content already
  /// shown) is instead kept as-is and marked done — retrying then risks a
  /// duplicated turn if the server actually did finish and persist.
  Future<bool> sendMessageStreaming({
    required String userId,
    required String message,
  }) async {
    if (_currentSession == null) {
      _sessionError = 'No active session';
      notifyListeners();
      return false;
    }

    final sessionId = _currentSession!.sessionId;
    final requestId = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final placeholderId = 'ai_${DateTime.now().millisecondsSinceEpoch}';

    _isSendingMessage = true;
    _sessionError = null;
    notifyListeners();

    _messages.add(
      TopicChatMessage(
        id: requestId,
        sessionId: sessionId,
        content: message,
        isUser: true,
        timestamp: DateTime.now(),
      ),
    );
    _messages.add(
      TopicChatMessage(
        id: placeholderId,
        sessionId: sessionId,
        content: '',
        isUser: false,
        timestamp: DateTime.now(),
      ),
    );
    notifyListeners();

    var receivedDone = false;

    try {
      await for (final event in repository.sendTopicMessageStream(
        sessionId: sessionId,
        userId: userId,
        message: message,
      )) {
        switch (event) {
          case TopicStreamThinking():
            break;

          case TopicStreamChunk(:final text):
            final idx = _messages.indexWhere((m) => m.id == placeholderId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(
                content: _messages[idx].content + text,
              );
              notifyListeners();
            }

          case TopicStreamDone(:final response):
            receivedDone = true;
            final idx = _messages.indexWhere((m) => m.id == placeholderId);
            if (idx != -1) {
              _messages[idx] = TopicChatMessage(
                id: response.messageId,
                sessionId: sessionId,
                content: response.response,
                isUser: false,
                timestamp: DateTime.now(),
                hints: response.educationalHints,
                llmMetadata: response.llmMetadata,
              );
            }

          case TopicStreamError(:final error):
            debugPrint('[StoryProvider] stream error event: $error');
            await _retryMessageWithoutStreaming(
              message: message,
              userId: userId,
              requestId: requestId,
              placeholderId: placeholderId,
              reason: error,
            );
            return _sessionError == null;
        }
      }

      if (!receivedDone) {
        final idx = _messages.indexWhere((m) => m.id == placeholderId);
        final partial = idx == -1 ? '' : _messages[idx].content.trim();
        if (partial.isEmpty) {
          await _retryMessageWithoutStreaming(
            message: message,
            userId: userId,
            requestId: requestId,
            placeholderId: placeholderId,
            reason: 'stream closed before sending a response',
          );
          return _sessionError == null;
        }
        // Partial content already visible — the server may have finished
        // and persisted on its side, so don't retry (would risk a
        // duplicated turn). Keep what streamed in and stop the spinner.
        debugPrint('[StoryProvider] stream closed without done; kept partial content');
      }
    } catch (e) {
      debugPrint('[StoryProvider] sendMessageStreaming exception: $e');
      await _retryMessageWithoutStreaming(
        message: message,
        userId: userId,
        requestId: requestId,
        placeholderId: placeholderId,
        reason: e.toString(),
      );
      return _sessionError == null;
    }

    _isSendingMessage = false;
    notifyListeners();
    return true;
  }

  bool _isUnauthorizedError(Object error) {
    final normalized = error.toString().toLowerCase();
    return normalized.contains('unauthorized') || normalized.contains('401');
  }

  Future<void> _retryMessageWithoutStreaming({
    required String message,
    required String userId,
    required String requestId,
    required String placeholderId,
    required String reason,
  }) async {
    debugPrint('[StoryProvider] retrying without streaming: $reason');
    _messages.removeWhere((m) => m.id == requestId || m.id == placeholderId);
    _isSendingMessage = false;

    if (_isUnauthorizedError(reason)) {
      _sessionError = 'Your login session expired. Please sign in again.';
      notifyListeners();
      return;
    }

    notifyListeners();
    await sendMessage(userId: userId, message: message);
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
    _mistakesSavedThisSession = 0;
    _wordsSavedThisSession = 0;
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
        jsonEncode(session.toCacheJson()),
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
      return TopicSession.fromCacheJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
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
          .map((s) => jsonEncode(s.toCacheJson()))
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
            .map(
              (s) => StoryListItem.fromCacheJson(
                jsonDecode(s) as Map<String, dynamic>,
              ),
            )
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
