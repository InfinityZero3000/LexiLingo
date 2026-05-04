import 'package:lexilingo_app/core/services/database_helper.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

class VocabLocalDataSource {
  final DatabaseHelper dbHelper;

  VocabLocalDataSource({required this.dbHelper});

  Future<List<VocabWord>> getWords() async {
    final db = await dbHelper.database;
    final userId = await UserScopeService.getActiveUserId();

    // Filter by userId when a user is logged in; fall back to unscoped rows
    // (userId IS NULL) for data created before auth was introduced.
    final List<Map<String, dynamic>> result;
    if (userId != null) {
      result = await db.query(
        'vocabulary',
        where: 'userId = ? OR userId IS NULL',
        whereArgs: [userId],
        orderBy: 'id DESC',
      );
    } else {
      result = await db.query('vocabulary', orderBy: 'id DESC');
    }

    return result
        .map(
          (e) => VocabWord(
            id: e['id'] as int?,
            word: e['word'] as String,
            definition: e['definition'] as String,
            isLearned: (e['isLearned'] as int? ?? 0) == 1,
            pronunciation: e['phonetic'] as String?,
            audioUrl: e['audioUrl'] as String?,
            example: e['example'] as String?,
            partOfSpeech: e['partOfSpeech'] as String?,
          ),
        )
        .toList();
  }

  Future<void> addWord(VocabWord word) async {
    final db = await dbHelper.database;
    final userId = await UserScopeService.getActiveUserId();
    await db.insert('vocabulary', {
      if (userId != null) 'userId': userId,
      'word': word.word,
      'definition': word.definition,
      'isLearned': word.isLearned ? 1 : 0,
      'phonetic': word.pronunciation ?? '',
      'audioUrl': word.audioUrl ?? '',
      'example': word.example ?? '',
      'partOfSpeech': word.partOfSpeech ?? '',
    });
  }
}
