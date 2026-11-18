import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_paged_list.dart';

const vocabularyLevels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
const vocabularyParts = [
  'noun',
  'verb',
  'adjective',
  'adverb',
  'preposition',
  'conjunction',
  'pronoun',
  'interjection',
];

class VocabularyWord {
  const VocabularyWord({
    required this.id,
    required this.word,
    required this.definition,
    this.translation,
    this.partOfSpeech = 'noun',
    this.pronunciation,
    this.level = 'A1',
  });

  final String id;
  final String word;
  final String definition;
  final String? translation;
  final String partOfSpeech;
  final String? pronunciation;
  final String level;

  /// The server stores the translation as text or as `{vi: ...}`.
  static String? _translation(Object? raw) {
    if (raw is Map && raw.isNotEmpty) {
      return (raw['vi'] ?? raw.values.first)?.toString();
    }
    final text = raw?.toString();
    return text == null || text.isEmpty ? null : text;
  }

  factory VocabularyWord.fromJson(Map<String, dynamic> j) => VocabularyWord(
    id: j['id']?.toString() ?? '',
    word: j['word']?.toString() ?? '',
    definition: j['definition']?.toString() ?? '',
    translation: _translation(j['translation']),
    partOfSpeech: j['part_of_speech']?.toString().toLowerCase() ?? 'noun',
    pronunciation: j['pronunciation']?.toString(),
    level: j['difficulty_level']?.toString().toUpperCase() ?? 'A1',
  );
}

class VocabularyRepository {
  VocabularyRepository({ApiClient? api}) : _api = api ?? ApiClient.instance;

  final ApiClient _api;

  Future<PageResult<VocabularyWord>> list(PageRequest request) async {
    final body = await _api.getData(
      ApiEndpoints.adminVocabulary,
      params: PaginationStyle.limitOffset.query(request),
    );
    return adminPage(body, VocabularyWord.fromJson);
  }

  /// The vocabulary routes take their fields as query parameters, not a body.
  Map<String, String> _query({
    required String word,
    required String definition,
    required String translation,
    required String partOfSpeech,
    required String pronunciation,
    required String level,
  }) => {
    'word': word,
    'definition': definition,
    'translation': translation,
    'part_of_speech': partOfSpeech,
    'pronunciation': pronunciation,
    'difficulty_level': level,
  };

  Future<void> save({
    String? id,
    required String word,
    required String definition,
    required String translation,
    required String partOfSpeech,
    required String pronunciation,
    required String level,
  }) async {
    final query = Uri(
      queryParameters: _query(
        word: word,
        definition: definition,
        translation: translation,
        partOfSpeech: partOfSpeech,
        pronunciation: pronunciation,
        level: level,
      ),
    ).query;
    if (id == null) {
      await _api.post('${ApiEndpoints.adminVocabulary}?$query');
    } else {
      await _api.put('${ApiEndpoints.adminVocabulary}/$id?$query');
    }
  }
}
