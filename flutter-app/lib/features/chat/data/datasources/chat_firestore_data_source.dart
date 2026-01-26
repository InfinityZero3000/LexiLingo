import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/message.dart';
import '../../../../core/services/firestore_service.dart';

abstract class ChatFirestoreDataSource {
  Future<void> saveMessage(String userId, String sessionId, Message message);
  Future<List<Message>> getSessionHistory(String userId, String sessionId);
  Future<List<String>> getUserSessions(String userId);
  Future<void> createSession(String userId, String sessionId, String title);
  Stream<List<Message>> watchSessionMessages(String userId, String sessionId);
}

class ChatFirestoreDataSourceImpl implements ChatFirestoreDataSource {
  final FirestoreService firestoreService;

  ChatFirestoreDataSourceImpl({required this.firestoreService});

  CollectionReference? _getSessionMessages(String userId, String sessionId) {
    return firestoreService
        .getUserChatSessions(userId)
        ?.doc(sessionId)
        .collection('messages');
  }

  @override
  Future<void> saveMessage(String userId, String sessionId, Message message) async {
    try {
      final messagesRef = _getSessionMessages(userId, sessionId);
      if (messagesRef == null) throw Exception('Invalid user ID');

      await messagesRef.add({
        'content': message.content,
        'isUser': message.isUser,
        'timestamp': message.timestamp.toIso8601String(),
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Update session's last message timestamp
      await firestoreService.getUserChatSessions(userId)?.doc(sessionId).update({
        'lastMessageAt': FieldValue.serverTimestamp(),
        'messageCount': FieldValue.increment(1),
      });
    } catch (e) {
      throw Exception('Failed to save message to Firestore: $e');
    }
  }

  @override
  Future<List<Message>> getSessionHistory(String userId, String sessionId) async {
    try {
      final messagesRef = _getSessionMessages(userId, sessionId);
      if (messagesRef == null) return [];

      final snapshot = await messagesRef.orderBy('timestamp').get();
      
      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Message(
          content: data['content'] as String,
          isUser: data['isUser'] as bool,
          timestamp: DateTime.parse(data['timestamp'] as String),
        );
      }).toList();
    } catch (e) {
      throw Exception('Failed to get session history from Firestore: $e');
    }
  }

  @override
  Future<List<String>> getUserSessions(String userId) async {
    try {
      final sessionsRef = firestoreService.getUserChatSessions(userId);
      if (sessionsRef == null) return [];

      final snapshot = await sessionsRef.orderBy('lastMessageAt', descending: true).get();
      
      return snapshot.docs.map((doc) => doc.id).toList();
    } catch (e) {
      throw Exception('Failed to get user sessions from Firestore: $e');
    }
  }

  @override
  Future<void> createSession(String userId, String sessionId, String title) async {
    try {
      await firestoreService.getUserChatSessions(userId)?.doc(sessionId).set({
        'title': title,
        'createdAt': FieldValue.serverTimestamp(),
        'lastMessageAt': FieldValue.serverTimestamp(),
        'messageCount': 0,
      });
    } catch (e) {
      throw Exception('Failed to create session in Firestore: $e');
    }
  }

  @override
  Stream<List<Message>> watchSessionMessages(String userId, String sessionId) {
    try {
      final messagesRef = _getSessionMessages(userId, sessionId);
      if (messagesRef == null) return Stream.value([]);

      return messagesRef.orderBy('timestamp').snapshots().map((snapshot) {
        return snapshot.docs.map((doc) {
          final data = doc.data() as Map<String, dynamic>;
          return Message(
            content: data['content'] as String,
            isUser: data['isUser'] as bool,
            timestamp: DateTime.parse(data['timestamp'] as String),
          );
        }).toList();
      });
    } catch (e) {
      throw Exception('Failed to watch session messages from Firestore: $e');
    }
  }
}
