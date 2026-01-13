import 'package:lexilingo_app/features/chat/data/datasources/chat_local_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_firestore_data_source.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource aiDataSource; // Gemini AI
  final ChatLocalDataSource? localDataSource; // SQLite cache
  final ChatFirestoreDataSource? firestoreDataSource; // Cloud backup

  ChatRepositoryImpl({
    required this.aiDataSource,
    this.localDataSource,
    this.firestoreDataSource,
  });

  @override
  Future<String> sendMessageToAI(String message) async {
    return await aiDataSource.sendMessage(message);
  }

  @override
  Future<void> saveMessage(Message message) async {
    // Save to local cache first
    if (localDataSource != null) {
      await localDataSource!.saveMessage(message);
    }
    
    // Backup to Firestore if available
    if (firestoreDataSource != null) {
      try {
        // TODO: Get userId and sessionId from auth service
        // For now, we'll need to pass these through the domain layer
      } catch (e) {
        // Firestore backup failed, not critical
      }
    }
  }

  @override
  Future<List<Message>> getChatHistory() async {
    if (localDataSource == null) return [];
    return await localDataSource!.getHistory();
  }
}
