import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

class VocabLocalDataSource {
  final DatabaseHelper dbHelper;

  VocabLocalDataSource({required this.dbHelper});

  Future<List<VocabWord>> getWords() async {
    final db = await dbHelper.database;
    final result = await db.query('vocabulary', orderBy: 'id DESC');
    
    return result.map((e) => VocabWord(
      id: e['id'] as int?,
      word: e['word'] as String,
      definition: e['definition'] as String,
      isLearned: (e['isLearned'] as int) == 1,
    )).toList();
  }

  Future<void> addWord(VocabWord word) async {
    final db = await dbHelper.database;
    await db.insert('vocabulary', {
      'word': word.word,
      'definition': word.definition,
      'isLearned': word.isLearned ? 1 : 0,
      'example': '', 
    });
  }
}
