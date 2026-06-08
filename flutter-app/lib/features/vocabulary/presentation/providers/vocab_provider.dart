import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/add_word_usecase.dart';
import 'package:lexilingo_app/features/vocabulary/domain/usecases/get_words_usecase.dart';

/// Result from the free Dictionary API lookup.
class DictionaryLookupResult {
  final String word;
  final String? pronunciation; // IPA
  final String? audioUrl;
  final String? definition;
  final String? example;
  final String? partOfSpeech;
  final bool found;

  const DictionaryLookupResult({
    required this.word,
    this.pronunciation,
    this.audioUrl,
    this.definition,
    this.example,
    this.partOfSpeech,
    required this.found,
  });
}

class VocabProvider extends ChangeNotifier {
  static const int _backendCollectionPageSize = 100;

  final GetWordsUseCase getWordsUseCase;
  final AddWordUseCase addWordUseCase;
  final ApiClient? _apiClient;
  final QuickSaveVocabularyService? _quickSaveService;
  StreamSubscription<QuickSaveVocabularyResult>? _savedWordsSubscription;
  List<VocabWord> _words = [];
  String? _errorMessage;
  bool _isLoading = false;
  String? _selectedTag;

  // Dictionary lookup state
  DictionaryLookupResult? _lookupResult;
  bool _isLookingUp = false;

  VocabProvider({
    required this.getWordsUseCase,
    required this.addWordUseCase,
    ApiClient? apiClient,
    QuickSaveVocabularyService? quickSaveService,
  }) : _apiClient = apiClient,
       _quickSaveService = quickSaveService {
    _savedWordsSubscription = _quickSaveService?.savedWords.listen((_) {
      unawaited(loadWords());
    });
    unawaited(loadWords());
    unawaited(loadDecks());
  }

  List<VocabWord> get words => _words;
  String? get errorMessage => _errorMessage;
  bool get isLoading => _isLoading;
  String? get selectedTag => _selectedTag;

  List<String> get availableTags {
    final tags = <String>{};
    for (final w in _words) {
      if (w.tags != null) tags.addAll(w.tags!);
    }
    final sorted = tags.toList()..sort();
    return sorted;
  }

  List<VocabWord> get filteredWords {
    if (_selectedTag == null) return _words;
    return _words.where((w) => w.tags?.contains(_selectedTag) == true).toList();
  }

  void setTagFilter(String? tag) {
    _selectedTag = tag;
    notifyListeners();
  }

  DictionaryLookupResult? get lookupResult => _lookupResult;
  bool get isLookingUp => _isLookingUp;

  Future<void> loadWords() async {
    _isLoading = true;
    notifyListeners();

    final result = await getWordsUseCase(NoParams());
    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
        _words = [];
      },
      (words) {
        _words = words;
        _errorMessage = null;
      },
    );

    // Merge with backend collection (words saved from book reader, YouTube, news).
    if (_apiClient != null) {
      try {
        final backendWords = await _fetchBackendCollection();
        final localWordSet = {for (final w in _words) w.word.toLowerCase()};
        final merged = [
          ..._words,
          ...backendWords.where(
            (w) => !localWordSet.contains(w.word.toLowerCase()),
          ),
        ];
        _words = merged;
      } catch (_) {
        // Backend unavailable — local words still shown.
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _savedWordsSubscription?.cancel();
    super.dispose();
  }

  Future<List<VocabWord>> _fetchBackendCollection() async {
    final response = await _apiClient!.get(
      '/vocabulary/collection?limit=$_backendCollectionPageSize',
    );
    final items = (response['items'] as List<dynamic>? ?? []);
    return items
        .map((item) {
          final vocab = item['vocabulary'] as Map<String, dynamic>?;
          if (vocab == null) return null;
          final word = vocab['word'] as String? ?? '';
          if (word.isEmpty) return null;
          final rawTags = vocab['tags'];
          final tags = rawTags is List
              ? rawTags.whereType<String>().toList()
              : null;
          return VocabWord(
            userVocabularyId: item['id'] as String?,
            word: word,
            definition: vocab['definition'] as String? ?? '',
            pronunciation: vocab['pronunciation'] as String?,
            audioUrl: vocab['audio_url'] as String?,
            partOfSpeech: vocab['part_of_speech'] as String?,
            isLearned: (item['status'] as String?) == 'mastered',
            tags: tags,
          );
        })
        .whereType<VocabWord>()
        .toList();
  }

  /// Look up a word in the free Dictionary API.
  /// Fills [lookupResult] with pronunciation, definition, example, partOfSpeech.
  Future<DictionaryLookupResult> lookupWord(String word) async {
    _isLookingUp = true;
    _lookupResult = null;
    notifyListeners();

    final trimmed = word.trim().toLowerCase();
    DictionaryLookupResult result;
    try {
      final uri = Uri.parse(
        'https://api.dictionaryapi.dev/api/v2/entries/en/$trimmed',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode == 200) {
        final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
        final entry = data[0] as Map<String, dynamic>;

        // Phonetics
        String? ipa;
        String? audio;
        final phonetics = entry['phonetics'] as List<dynamic>? ?? [];
        for (final p in phonetics) {
          final pm = p as Map<String, dynamic>;
          ipa ??= pm['text'] as String?;
          if (audio == null) {
            final a = pm['audio'] as String?;
            if (a != null && a.isNotEmpty) audio = a;
          }
          if (ipa != null && audio != null) break;
        }

        // Meanings
        String? definition;
        String? example;
        String? pos;
        final meanings = entry['meanings'] as List<dynamic>? ?? [];
        if (meanings.isNotEmpty) {
          final meaning = meanings[0] as Map<String, dynamic>;
          pos = meaning['partOfSpeech'] as String?;
          final defs = meaning['definitions'] as List<dynamic>? ?? [];
          if (defs.isNotEmpty) {
            final def = defs[0] as Map<String, dynamic>;
            definition = def['definition'] as String?;
            example = def['example'] as String?;
          }
        }

        result = DictionaryLookupResult(
          word: word,
          pronunciation: ipa,
          audioUrl: audio,
          definition: definition,
          example: example,
          partOfSpeech: pos,
          found: true,
        );
      } else {
        result = DictionaryLookupResult(word: word, found: false);
      }
    } catch (_) {
      result = DictionaryLookupResult(word: word, found: false);
    }

    _lookupResult = result;
    _isLookingUp = false;
    notifyListeners();
    return result;
  }

  void clearLookup() {
    _lookupResult = null;
    notifyListeners();
  }

  Future<bool> addWord(
    String word,
    String definition, {
    String? pronunciation,
    String? audioUrl,
    String? example,
    String? partOfSpeech,
  }) async {
    final result = await addWordUseCase(
      AddWordParams(
        word: word,
        definition: definition,
        pronunciation: pronunciation,
        audioUrl: audioUrl,
        example: example,
        partOfSpeech: partOfSpeech,
      ),
    );
    bool success = false;
    result.fold(
      (failure) {
        _errorMessage = _getFailureMessage(failure);
      },
      (_) {
        _errorMessage = null;
        success = true;
      },
    );
    await loadWords();
    return success;
  }

  String _getFailureMessage(Failure failure) {
    if (failure is ServerFailure) {
      return failure.message;
    } else if (failure is NetworkFailure) {
      return 'Network error. Please check your internet connection.';
    } else if (failure is CacheFailure) {
      return 'Local storage error.';
    } else {
      return 'An error occurred. Please try again.';
    }
  }

  // ===== Vocabulary Decks =====
  List<VocabularyDeck> _decks = [];
  List<VocabularyDeck> get decks => _decks;

  Future<void> loadDecks() async {
    if (_apiClient == null) return;
    _isLoading = true;
    notifyListeners();

    try {
      final response = await _apiClient.get('/vocabulary/decks');
      final items = response['data'] ?? response;
      if (items is List) {
        _decks = items
            .map((d) => VocabularyDeck.fromJson(d as Map<String, dynamic>))
            .toList();
      } else {
        _decks = [];
      }
      _errorMessage = null;
    } catch (e) {
      _errorMessage = 'Failed to load decks: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> createDeck(
    String name,
    String? description,
    String color,
  ) async {
    if (_apiClient == null) return false;
    _isLoading = true;
    notifyListeners();

    try {
      final descParam = description != null
          ? '&description=${Uri.encodeComponent(description)}'
          : '';
      final colorParam = '&color=${Uri.encodeComponent(color)}';
      await _apiClient.post(
        '/vocabulary/decks?name=${Uri.encodeComponent(name)}'
        '$descParam$colorParam',
      );
      _errorMessage = null;
      await loadDecks();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to create deck: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addWordToDeck(String deckId, String userVocabularyId) async {
    if (_apiClient == null) return false;
    try {
      await _apiClient.post(
        '/vocabulary/decks/$deckId/items',
        body: {'user_vocabulary_id': userVocabularyId},
      );
      await loadDecks();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to add word to deck: $e';
      return false;
    }
  }

  Future<bool> removeWordFromDeck(
    String deckId,
    String userVocabularyId,
  ) async {
    if (_apiClient == null) return false;
    try {
      await _apiClient.delete(
        '/vocabulary/decks/$deckId/items/$userVocabularyId',
      );
      await loadDecks();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to remove word from deck: $e';
      return false;
    }
  }

  Future<bool> deleteDeck(String deckId) async {
    if (_apiClient == null) return false;
    _isLoading = true;
    notifyListeners();
    try {
      await _apiClient.delete('/vocabulary/decks/$deckId');
      await loadDecks();
      return true;
    } catch (e) {
      _errorMessage = 'Failed to delete deck: $e';
      return false;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}

class VocabularyDeck {
  final String id;
  final String name;
  final String? description;
  final String color;
  final bool isPublic;
  final int itemCount;

  const VocabularyDeck({
    required this.id,
    required this.name,
    this.description,
    required this.color,
    this.isPublic = false,
    this.itemCount = 0,
  });

  factory VocabularyDeck.fromJson(Map<String, dynamic> json) {
    return VocabularyDeck(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      color: json['color'] as String? ?? "#2196F3",
      isPublic: json['is_public'] as bool? ?? false,
      itemCount: json['item_count'] as int? ?? 0,
    );
  }
}
