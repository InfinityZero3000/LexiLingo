import 'package:flutter/foundation.dart';
import '../../domain/entities/chat_message.dart';
import '../../domain/entities/chat_session.dart';
import '../../domain/repositories/chat_repository.dart';
import '../../domain/usecases/create_session_usecase.dart';
import '../../domain/usecases/get_chat_history_usecase.dart';
import '../../domain/usecases/get_sessions_usecase.dart';
import '../../domain/usecases/send_message_usecase.dart';

/// State management for chat feature using Provider
class ChatProvider extends ChangeNotifier {
  final CreateSessionUseCase createSessionUseCase;
  final GetSessionsUseCase getSessionsUseCase;
  final GetChatHistoryUseCase getChatHistoryUseCase;
  final SendMessageUseCase sendMessageUseCase;

  ChatProvider({
    required this.createSessionUseCase,
    required this.getSessionsUseCase,
    required this.getChatHistoryUseCase,
    required this.sendMessageUseCase,
  });

  ChatSession? _currentSession;
  List<ChatSession> _sessions = [];
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  bool _isSending = false;
  String? _error;
  AIModel _selectedModel = AIModel.gemini;
  
  // Pagination for messages
  bool _hasMoreMessages = true;
  bool _isLoadingMoreMessages = false;
  int _messagesPageSize = 20;
  
  // Pagination for sessions
  bool _hasMoreSessions = true;
  bool _isLoadingMoreSessions = false;
  int _sessionsPageSize = 10;

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  AIModel get selectedModel => _selectedModel;
  bool get hasCurrentSession => _currentSession != null;
  bool get hasMoreMessages => _hasMoreMessages;
  bool get isLoadingMoreMessages => _isLoadingMoreMessages;
  bool get hasMoreSessions => _hasMoreSessions;
  bool get isLoadingMoreSessions => _isLoadingMoreSessions;

  Future<void> createNewSession(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await createSessionUseCase(userId);
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (session) {
        _currentSession = session;
        _messages = [];
        _sessions.insert(0, session);
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> loadSessions(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    final result = await getSessionsUseCase(userId);
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (sessions) {
        _sessions = sessions.take(_sessionsPageSize).toList();
        _hasMoreSessions = sessions.length > _sessionsPageSize;
        _isLoading = false;
        notifyListeners();
      },
    );
  }
  
  Future<void> loadMoreSessions(String userId) async {
    if (_isLoadingMoreSessions || !_hasMoreSessions) return;
    
    _isLoadingMoreSessions = true;
    notifyListeners();
    
    final result = await getSessionsUseCase(userId);
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoadingMoreSessions = false;
        notifyListeners();
      },
      (sessions) {
        final startIndex = _sessions.length;
        final endIndex = startIndex + _sessionsPageSize;
        final newSessions = sessions.skip(startIndex).take(_sessionsPageSize).toList();
        _sessions.addAll(newSessions);
        _hasMoreSessions = sessions.length > endIndex;
        _isLoadingMoreSessions = false;
        notifyListeners();
      },
    );
  }

  Future<void> selectSession(ChatSession session) async {
    _currentSession = session;
    _error = null;
    _messages = []; // Clear messages when switching session
    _hasMoreMessages = true; // Reset pagination
    notifyListeners();
    await loadChatHistory(session.id);
  }

  Future<void> loadChatHistory(String sessionId) async {
    _isLoading = true;
    notifyListeners();

    final result = await getChatHistoryUseCase(sessionId);
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoading = false;
        notifyListeners();
      },
      (messages) {
        // Load only the last N messages initially (most recent)
        final recentMessages = messages.length > _messagesPageSize 
            ? messages.skip(messages.length - _messagesPageSize).toList()
            : messages;
        _messages = recentMessages;
        _hasMoreMessages = messages.length > _messagesPageSize;
        _isLoading = false;
        notifyListeners();
      },
    );
  }
  
  Future<void> loadMoreMessages() async {
    if (_currentSession == null || _isLoadingMoreMessages || !_hasMoreMessages) return;
    
    _isLoadingMoreMessages = true;
    notifyListeners();
    
    final result = await getChatHistoryUseCase(_currentSession!.id);
    result.fold(
      (failure) {
        _error = failure.message;
        _isLoadingMoreMessages = false;
        notifyListeners();
      },
      (allMessages) {
        // Calculate how many messages to load
        final currentCount = _messages.length;
        final totalCount = allMessages.length;
        
        if (currentCount >= totalCount) {
          _hasMoreMessages = false;
          _isLoadingMoreMessages = false;
          notifyListeners();
          return;
        }
        
        // Load older messages (from the beginning)
        final startIndex = totalCount - currentCount - _messagesPageSize;
        final endIndex = totalCount - currentCount;
        
        if (startIndex < 0) {
          // Load all remaining messages
          final olderMessages = allMessages.take(endIndex).toList();
          _messages.insertAll(0, olderMessages);
          _hasMoreMessages = false;
        } else {
          // Load next batch
          final olderMessages = allMessages.skip(startIndex).take(_messagesPageSize).toList();
          _messages.insertAll(0, olderMessages);
          _hasMoreMessages = startIndex > 0;
        }
        
        _isLoadingMoreMessages = false;
        notifyListeners();
      },
    );
  }

  Future<void> sendMessage(String content, {required String userId}) async {
    if (_currentSession == null) {
      _error = 'No active session';
      notifyListeners();
      return;
    }

    if (content.trim().isEmpty) return;

    _isSending = true;
    _error = null;
    
    final tempUserMessage = ChatMessage(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      sessionId: _currentSession!.id,
      content: content.trim(),
      role: MessageRole.user,
      timestamp: DateTime.now(),
      status: MessageStatus.sending,
    );
    
    _messages.add(tempUserMessage);
    notifyListeners();

    final params = SendMessageParams(
      sessionId: _currentSession!.id,
      userId: userId,
      message: content.trim(),
      model: _selectedModel,
      conversationHistory: _messages.where((m) => m.status == MessageStatus.sent).toList(),
    );

    final result = await sendMessageUseCase(params);
    result.fold(
      (failure) {
        final index = _messages.indexWhere((m) => m.id == tempUserMessage.id);
        if (index != -1) {
          _messages[index] = tempUserMessage.copyWith(
            status: MessageStatus.error,
            error: failure.message,
          );
        }
        _error = failure.message;
        _isSending = false;
        notifyListeners();
      },
      (aiMessage) {
        _messages.removeWhere((m) => m.id.startsWith('temp_'));
        loadChatHistory(_currentSession!.id);
        _isSending = false;
      },
    );
  }

  void switchModel(AIModel model) {
    _selectedModel = model;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    _currentSession = null;
    _sessions = [];
    _messages = [];
    _isLoading = false;
    _isSending = false;
    _error = null;
    _selectedModel = AIModel.gemini;
    _hasMoreMessages = true;
    _isLoadingMoreMessages = false;
    _hasMoreSessions = true;
    _isLoadingMoreSessions = false;
    notifyListeners();
  }
}
