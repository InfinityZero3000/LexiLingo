import 'package:lexilingo_app/core/storage/fresh_preferences.dart';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/http_status.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/services/encrypted_local_cache_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocab_repository.dart';
import 'package:lexilingo_app/features/vocabulary/data/datasources/vocab_local_data_source.dart';

/// Vocabulary Repository Implementation
/// Uses the local database when there is one. On web there is none, and the
/// queue that syncs offline adds is native-only, so a word added there is kept
/// in a per-learner pending list until the server has it.
class VocabRepositoryImpl implements VocabRepository {
  final VocabLocalDataSource? localDataSource;
  final EncryptedLocalCacheService _secureCache =
      EncryptedLocalCacheService.instance;
  final BackgroundSyncQueueService _syncQueue =
      BackgroundSyncQueueService.instance;

  final ApiClient? _apiClient;

  static const _secureKey = 'vocab:words:v1';

  /// Words added on web that the server may not have yet, under a per-user key.
  static const _pendingKey = 'vocab_pending_words';

  /// Pre-per-user global list. Whoever signs in first owns it.
  static const _legacyWebKey = 'vocab_words_json';

  bool _flushing = false;

  VocabRepositoryImpl({required this.localDataSource, ApiClient? apiClient})
    : _apiClient = apiClient;

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
        debugPrint('Failed to get vocabulary words: ${e.toString()}');
        return const Left(CacheFailure());
      }
    }

    // Web: the words this learner added that the server has not confirmed.
    try {
      final pending = await _syncedPendingWords(userScope);
      return Right(_fromJsonList(pending).reversed.toList());
    } catch (e) {
      debugPrint('Failed to get vocabulary words: $e');
      return const Left(CacheFailure());
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
        debugPrint('Failed to add vocabulary word: ${e.toString()}');
        return const Left(CacheFailure());
      }
    }

    // Web: keep the word until the server has it; it is never dropped.
    try {
      await _locked(() async {
        final pending = await _loadPending(userScope);
        pending.add({
          'word': word.word,
          'definition': word.definition,
          'isLearned': word.isLearned,
          if (word.pronunciation != null) 'pronunciation': word.pronunciation,
          if (word.audioUrl != null) 'audioUrl': word.audioUrl,
          if (word.example != null) 'example': word.example,
          if (word.partOfSpeech != null) 'partOfSpeech': word.partOfSpeech,
        });
        await _savePending(userScope, pending);
      });
      await _syncedPendingWords(userScope);
      return const Right(null);
    } catch (e) {
      debugPrint('Failed to add vocabulary word: $e');
      return const Left(CacheFailure());
    }
  }

  String _pendingStorageKey(String userScope) => 'u:$userScope:$_pendingKey';

  /// Every read-modify-write of the pending list goes through here, one at a
  /// time. The flush sends words over the network between its own reads and
  /// writes, so without this a word added meanwhile is overwritten and lost.
  Future<void> _lockTail = Future.value();

  Future<T> _locked<T>(Future<T> Function() action) {
    final result = _lockTail.then((_) => action());
    _lockTail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  /// The learner's pending list, after folding in the legacy global list when
  /// this is a signed-in learner and nobody has claimed it yet. Only call it
  /// inside [_locked].
  Future<List<Map<String, dynamic>>> _loadPending(String userScope) async {
    final prefs = await freshPreferences();
    final raw = prefs.getString(_pendingStorageKey(userScope));
    final pending = raw == null || raw.isEmpty
        ? <Map<String, dynamic>>[]
        : (jsonDecode(raw) as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

    final legacyRaw = prefs.getString(_legacyWebKey);
    if (userScope != 'anonymous' && legacyRaw != null) {
      try {
        final seen = {for (final w in pending) _wordKey(w)};
        for (final item in (jsonDecode(legacyRaw) as List)) {
          final map = Map<String, dynamic>.from(item as Map);
          if (seen.add(_wordKey(map))) pending.add(map);
        }
        await _savePending(userScope, pending);
      } catch (e) {
        debugPrint('Legacy vocabulary words could not be read: $e');
        return pending;
      }
      await prefs.remove(_legacyWebKey);
    }
    return pending;
  }

  Future<void> _savePending(
    String userScope,
    List<Map<String, dynamic>> pending,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_pendingStorageKey(userScope), jsonEncode(pending));
  }

  static String _wordKey(Map<String, dynamic> item) =>
      '${item['word']}'.trim().toLowerCase();

  /// What the server will never accept for this word: an empty or too long
  /// word or definition, or a word it already has. Keeping it would block
  /// every word behind it, so it is dropped.
  static bool _isPermanentRejection(Object error) =>
      const {400, 409, 422}.contains(httpStatusOf(error));

  /// Sends what the server does not have yet, oldest first, and returns what
  /// is still pending.
  ///
  /// The queue is re-read before each word and the sent word is removed by its
  /// text, never by position or from an earlier copy, so words added during a
  /// request survive. Before each request it checks the signed-in learner is
  /// still the one these words belong to: the request carries the current
  /// token, and a word must never be sent as someone else. A word the server
  /// permanently refuses is dropped; any other failure stops the run and keeps
  /// the rest.
  Future<List<Map<String, dynamic>>> _syncedPendingWords(
    String userScope,
  ) async {
    final api = _apiClient;
    if (api != null && userScope != 'anonymous' && !_flushing) {
      _flushing = true;
      try {
        while (true) {
          final next = await _locked(() async {
            final pending = await _loadPending(userScope);
            return pending.isEmpty ? null : pending.first;
          });
          if (next == null) break;
          if (await UserScopeService.getScopeOrDefault() != userScope) break;

          try {
            await api.post(
              '/vocabulary/collection/quick-save',
              body: {
                'word': next['word'],
                'source_type': 'manual',
                if (next['definition'] != null)
                  'definition': next['definition'],
                if (next['partOfSpeech'] != null)
                  'part_of_speech': next['partOfSpeech'],
              },
            );
          } catch (e) {
            if (!_isPermanentRejection(e)) {
              debugPrint('Vocabulary word kept for a later sync: $e');
              break;
            }
            debugPrint('Vocabulary word dropped, the server refuses it: $e');
          }

          final key = _wordKey(next);
          await _locked(() async {
            final pending = await _loadPending(userScope);
            final at = pending.indexWhere((w) => _wordKey(w) == key);
            if (at == -1) return;
            pending.removeAt(at);
            await _savePending(userScope, pending);
          });
        }
      } finally {
        _flushing = false;
      }
    }
    return _locked(() => _loadPending(userScope));
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
            if (w.translation != null) 'translation': w.translation,
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
        translation: m['translation'] as Map<String, dynamic>?,
      );
    }).toList();
  }
}
