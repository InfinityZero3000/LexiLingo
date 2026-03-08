import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';

/// Vocabulary Repository Implementation
/// Uses local database when available, falls back to SharedPreferences (web).
class VocabRepositoryImpl implements VocabRepository {
  final VocabLocalDataSource? localDataSource;

  static const _prefsKey = 'vocab_words_json';

  VocabRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async {
    if (localDataSource != null) {
      try {
        final words = await localDataSource!.getWords();
        return Right(words);
      } catch (e) {
        return Left(
          CacheFailure('Failed to get vocabulary words: ${e.toString()}'),
        );
      }
    }

    // Fallback: SharedPreferences (works on web)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const Right([]);

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final words = list.asMap().entries.map((entry) {
        final m = entry.value as Map<String, dynamic>;
        return VocabWord(
          id: entry.key,
          word: m['word'] as String? ?? '',
          definition: m['definition'] as String? ?? '',
          isLearned: m['isLearned'] as bool? ?? false,
        );
      }).toList();
      return Right(words.reversed.toList()); // newest first
    } catch (e) {
      return Left(CacheFailure('Failed to get vocabulary words: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async {
    if (localDataSource != null) {
      try {
        await localDataSource!.addWord(word);
        return const Right(null);
      } catch (e) {
        return Left(
          CacheFailure('Failed to add vocabulary word: ${e.toString()}'),
        );
      }
    }

    // Fallback: SharedPreferences (works on web)
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      final List<dynamic> list = (raw != null && raw.isNotEmpty)
          ? jsonDecode(raw) as List<dynamic>
          : [];

      list.add({
        'word': word.word,
        'definition': word.definition,
        'isLearned': word.isLearned,
      });

      await prefs.setString(_prefsKey, jsonEncode(list));
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to add vocabulary word: $e'));
    }
  }
}
