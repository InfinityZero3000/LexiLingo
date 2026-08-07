import 'dart:async';

import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Single source of truth for "does the user already know this word" across
/// reading/watching screens (News, YouTube, Book reader).
///
/// Before this existed, each screen tracked "saved" words as local widget
/// state that reset on every app restart, even though the real answer
/// (the user's saved vocabulary collection) was already persisted on the
/// backend — this service is the missing read path, not a new store.
class KnownWordsService {
  final VocabularyRepository vocabularyRepository;
  Set<String>? _cache;
  StreamSubscription<QuickSaveVocabularyResult>? _quickSaveSub;

  KnownWordsService({
    required this.vocabularyRepository,
    QuickSaveVocabularyService? quickSaveVocabularyService,
  }) {
    // Keep the cache live within the session: a word saved on one screen
    // should read as "known" on another without waiting for a refetch.
    _quickSaveSub = quickSaveVocabularyService?.savedWords.listen((result) {
      if (result.normalizedWord.isNotEmpty) {
        addKnownWord(result.normalizedWord);
      }
    });
  }

  /// Returns the user's known words, lowercased. Cached for the app
  /// session; pass [forceRefresh] to bypass the cache (e.g. pull-to-refresh).
  Future<Set<String>> getKnownWords({bool forceRefresh = false}) async {
    if (_cache != null && !forceRefresh) return _cache!;

    // ponytail: flat 500-word ceiling, not paginated — a learner with a
    // bigger saved collection will see words past this cut-off read as
    // "unknown" in reading/watching screens. Paginate here if that's ever
    // a real complaint.
    final result = await vocabularyRepository.getUserCollection(limit: 500);
    return result.fold(
      (_) => _cache ?? const {},
      (items) {
        _cache = items
            .map((item) => item.word?.trim().toLowerCase())
            .whereType<String>()
            .where((word) => word.isNotEmpty)
            .toSet();
        return _cache!;
      },
    );
  }

  void addKnownWord(String word) {
    final normalized = word.trim().toLowerCase();
    if (normalized.isEmpty) return;
    _cache = {...?_cache, normalized};
  }

  void dispose() {
    _quickSaveSub?.cancel();
  }
}
