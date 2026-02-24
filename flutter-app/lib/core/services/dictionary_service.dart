import 'dart:convert';

import 'package:http/http.dart' as http;

/// Definition result from the Free Dictionary API.
class WordDefinition {
  final String word;
  final String? phonetic;
  final List<MeaningEntry> meanings;

  const WordDefinition({
    required this.word,
    this.phonetic,
    required this.meanings,
  });
}

class MeaningEntry {
  final String partOfSpeech;
  final List<String> definitions;
  final List<String> examples;
  final List<String> synonyms;

  const MeaningEntry({
    required this.partOfSpeech,
    required this.definitions,
    required this.examples,
    required this.synonyms,
  });
}

/// Fetches word definitions from the Free Dictionary API.
///
/// Endpoint: https://api.dictionaryapi.dev/api/v2/entries/en/<word>
class DictionaryService {
  static const _baseUrl = 'https://api.dictionaryapi.dev/api/v2/entries/en';
  final http.Client _client;

  DictionaryService({http.Client? client}) : _client = client ?? http.Client();

  Future<WordDefinition?> lookup(String word) async {
    if (word.isEmpty) return null;
    final clean = word.toLowerCase().trim();
    try {
      final response = await _client
          .get(Uri.parse('$_baseUrl/$clean'))
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final List<dynamic> data = jsonDecode(response.body) as List<dynamic>;
      if (data.isEmpty) return null;

      final entry = data.first as Map<String, dynamic>;
      final phonetics = entry['phonetics'] as List<dynamic>? ?? [];
      final String? phonetic = phonetics
          .map((p) => (p as Map<String, dynamic>)['text'] as String?)
          .firstWhere((t) => t != null && t.isNotEmpty, orElse: () => null);

      final rawMeanings = entry['meanings'] as List<dynamic>? ?? [];
      final meanings = rawMeanings.map((m) {
        final map = m as Map<String, dynamic>;
        final defs = (map['definitions'] as List<dynamic>? ?? [])
            .take(3)
            .map((d) {
              final dm = d as Map<String, dynamic>;
              return (dm['definition'] as String?) ?? '';
            })
            .where((s) => s.isNotEmpty)
            .toList();

        final examples = (map['definitions'] as List<dynamic>? ?? [])
            .take(3)
            .map((d) {
              final dm = d as Map<String, dynamic>;
              return (dm['example'] as String?) ?? '';
            })
            .where((s) => s.isNotEmpty)
            .toList();

        final synonyms = (map['synonyms'] as List<dynamic>? ?? [])
            .take(5)
            .map((s) => s.toString())
            .toList();

        return MeaningEntry(
          partOfSpeech: (map['partOfSpeech'] as String?) ?? '',
          definitions: defs,
          examples: examples,
          synonyms: synonyms,
        );
      }).toList();

      return WordDefinition(
        word: clean,
        phonetic: phonetic,
        meanings: meanings,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
