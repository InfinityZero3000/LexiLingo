import 'package:lexilingo_app/features/chat/data/datasources/chat_local_data_source.dart';
import 'package:lexilingo_app/features/chat/data/datasources/chat_remote_data_source.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';
import 'package:lexilingo_app/features/chat/domain/repositories/chat_repository.dart';

class ChatRepositoryImpl implements ChatRepository {
  final ChatRemoteDataSource remoteDataSource;
  final ChatLocalDataSource localDataSource;

  ChatRepositoryImpl({required this.remoteDataSource, required this.localDataSource});

  @override
  Future<String> sendMessageToAI(String message) async {
    return await remoteDataSource.sendMessage(message);
  }

  @override
  Future<void> saveMessage(Message message) async {
    await localDataSource.saveMessage(message);
  }

  @override
  Future<List<Message>> getChatHistory() async {
    return await localDataSource.getHistory();
  }
}
