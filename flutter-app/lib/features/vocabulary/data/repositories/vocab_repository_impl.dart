import 'dart:convert';
import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/encrypted_local_cache_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';

/// Vocabulary Repository Implementation
/// Uses local database when available, falls back to SharedPreferences (web).
class VocabRepositoryImpl implements VocabRepository {
  final VocabLocalDataSource? localDataSource;
  final EncryptedLocalCacheService _secureCache =
      EncryptedLocalCacheService.instance;
  final BackgroundSyncQueueService _syncQueue =
      BackgroundSyncQueueService.instance;

  static const _prefsKey = 'vocab_words_json';
  static const _secureKey = 'vocab:words:v1';

  VocabRepositoryImpl({required this.localDataSource});

  @override
  Future<Either<Failure, List<VocabWord>>> getWords() async {
    final userScope = await UserScopeService.getScopeOrDefault();

    if (localDataSource != null) {
      try {
        final words = await localDataSource!.getWords();
        await _secureCache.putJson(
          userScope: userScope,
          namespace: 'vocab',
          key: _secureKey,
          value: _toJsonList(words),
        );
        return Right(words);
      } catch (e) {
        final cached = await _secureCache.getList(
          userScope: userScope,
          namespace: 'vocab',
          key: _secureKey,
          enforceTtl: false,
        );
        if (cached != null) {
          return Right(_fromJsonList(cached));
        }
        return Left(
          CacheFailure('Failed to get vocabulary words: ${e.toString()}'),
        );
      }
    }

    // Fallback: encrypted cache (works across platforms).
    try {
      final cached = await _secureCache.getList(
        userScope: userScope,
        namespace: 'vocab',
        key: _secureKey,
        enforceTtl: false,
      );
      if (cached != null) {
        return Right(_fromJsonList(cached));
      }

      // Compatibility migration from legacy SharedPreferences cache.
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return const Right([]);

      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      final words = _fromJsonList(list);

      await _secureCache.putJson(
        userScope: userScope,
        namespace: 'vocab',
        key: _secureKey,
        value: list,
      );
      return Right(words.reversed.toList()); // newest first
    } catch (e) {
      return Left(CacheFailure('Failed to get vocabulary words: $e'));
    }
  }

  @override
  Future<Either<Failure, void>> addWord(VocabWord word) async {
    final userScope = await UserScopeService.getScopeOrDefault();

    if (localDataSource != null) {
      try {
        await localDataSource!.addWord(word);
        final words = await localDataSource!.getWords();
        await _secureCache.putJson(
          userScope: userScope,
          namespace: 'vocab',
          key: _secureKey,
          value: _toJsonList(words),
        );
        try {
          await _enqueueVocabSync(userScope, word);
        } catch (_) {
          // Local success should not fail when background queue is unavailable.
        }
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
        if (word.pronunciation != null) 'pronunciation': word.pronunciation,
        if (word.audioUrl != null) 'audioUrl': word.audioUrl,
        if (word.example != null) 'example': word.example,
        if (word.partOfSpeech != null) 'partOfSpeech': word.partOfSpeech,
      });

      await prefs.setString(_prefsKey, jsonEncode(list));
      await _secureCache.putJson(
        userScope: userScope,
        namespace: 'vocab',
        key: _secureKey,
        value: list,
      );
      try {
        await _enqueueVocabSync(userScope, word);
      } catch (_) {
        // Local success should not fail when background queue is unavailable.
      }
      return const Right(null);
    } catch (e) {
      return Left(CacheFailure('Failed to add vocabulary word: $e'));
    }
  }

  Future<void> _enqueueVocabSync(String userScope, VocabWord word) async {
    // Avoid queueing for anonymous scope (not authenticated yet).
    if (userScope == 'anonymous') return;

    final idempotencyKey =
        'vocab-$userScope-${word.word.toLowerCase()}-${DateTime.now().millisecondsSinceEpoch}';
    await _syncQueue.enqueue(
      userScope: userScope,
      queueType: 'vocab.add_word.v1',
      idempotencyKey: idempotencyKey,
      payload: {
        'word': word.word,
        'definition': word.definition,
        'pronunciation': word.pronunciation,
        'example': word.example,
        'partOfSpeech': word.partOfSpeech,
        'source_type': 'manual',
      },
    );
  }

  List<Map<String, dynamic>> _toJsonList(List<VocabWord> words) {
    return words
        .map(
          (w) => {
            'id': w.id,
            'word': w.word,
            'definition': w.definition,
            'isLearned': w.isLearned,
            if (w.pronunciation != null) 'pronunciation': w.pronunciation,
            if (w.audioUrl != null) 'audioUrl': w.audioUrl,
            if (w.example != null) 'example': w.example,
            if (w.partOfSpeech != null) 'partOfSpeech': w.partOfSpeech,
          },
        )
        .toList();
  }

  List<VocabWord> _fromJsonList(List<dynamic> list) {
    return list.asMap().entries.map((entry) {
      final m = entry.value as Map<String, dynamic>;
      return VocabWord(
        id: (m['id'] as num?)?.toInt() ?? entry.key,
        word: m['word'] as String? ?? '',
        definition: m['definition'] as String? ?? '',
        isLearned: m['isLearned'] as bool? ?? false,
        pronunciation: m['pronunciation'] as String?,
        audioUrl: m['audioUrl'] as String?,
        example: m['example'] as String?,
        partOfSpeech: m['partOfSpeech'] as String?,
      );
    }).toList();
  }
}
