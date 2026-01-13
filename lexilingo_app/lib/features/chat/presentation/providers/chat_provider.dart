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

  ChatSession? get currentSession => _currentSession;
  List<ChatSession> get sessions => _sessions;
  List<ChatMessage> get messages => _messages;
  bool get isLoading => _isLoading;
  bool get isSending => _isSending;
  String? get error => _error;
  AIModel get selectedModel => _selectedModel;
  bool get hasCurrentSession => _currentSession != null;

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
        _sessions = sessions;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> selectSession(ChatSession session) async {
    _currentSession = session;
    _error = null;
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
        _messages = messages;
        _isLoading = false;
        notifyListeners();
      },
    );
  }

  Future<void> sendMessage(String content) async {
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
    notifyListeners();
  }
}
