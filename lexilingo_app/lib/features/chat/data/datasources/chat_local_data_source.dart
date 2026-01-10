import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/chat/domain/entities/message.dart';

class ChatLocalDataSource {
  final DatabaseHelper dbHelper;

  ChatLocalDataSource({required this.dbHelper});

  Future<void> saveMessage(Message message) async {
    final db = await dbHelper.database;
    await db.insert('chat_history', {
      'message': message.content,
      'isUser': message.isUser ? 1 : 0,
      'timestamp': message.timestamp.toIso8601String(),
    });
  }

  Future<List<Message>> getHistory() async {
    final db = await dbHelper.database;
    final result = await db.query('chat_history', orderBy: 'timestamp ASC');
    return result.map((e) => Message(
      content: e['message'] as String,
      isUser: (e['isUser'] as int) == 1,
      timestamp: DateTime.parse(e['timestamp'] as String),
    )).toList();
  }
}
