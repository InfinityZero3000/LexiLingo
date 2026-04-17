/// Tests for DictionaryService — Phase 6
///
/// Covers: WordDefinition, MeaningEntry constructors,
///         DictionaryService.lookup() with mocked HTTP client
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lexilingo_app/core/services/dictionary_service.dart';

// ── Sample API response matching Free Dictionary API format ──────────────────
const _sampleResponseJson = '''
[
  {
    "word": "hello",
    "phonetics": [
      {"text": "/heh-LOH/", "audio": "https://example.com/hello.mp3"},
      {"text": "", "audio": ""}
    ],
    "meanings": [
      {
        "partOfSpeech": "exclamation",
        "definitions": [
          {
            "definition": "Used as a greeting or to begin a telephone conversation.",
            "example": "Hello, how are you?",
            "synonyms": ["hi", "hey", "howdy", "greetings", "salutation", "good day"],
            "antonyms": []
          },
          {
            "definition": "An expression of surprise.",
            "example": "Hello! What is going on here?",
            "synonyms": [],
            "antonyms": []
          },
          {
            "definition": "A call to attract attention.",
            "example": "Hello! Anybody there?",
            "synonyms": [],
            "antonyms": []
          },
          {
            "definition": "A fourth definition - should be ignored (max 3).",
            "example": "",
            "synonyms": [],
            "antonyms": []
          }
        ],
        "synonyms": ["hi", "hey"],
        "antonyms": []
      },
      {
        "partOfSpeech": "noun",
        "definitions": [
          {
            "definition": "An utterance of hello.",
            "example": "She gave a friendly hello.",
            "synonyms": [],
            "antonyms": []
          }
        ],
        "synonyms": [],
        "antonyms": []
      }
    ]
  }
]
''';

void main() {
  // =========================================================================
  // MeaningEntry
  // =========================================================================
  group('MeaningEntry', () {
    test('constructor stores all fields', () {
      const m = MeaningEntry(
        partOfSpeech: 'noun',
        definitions: ['A greeting.'],
        examples: ['Hello there.'],
        synonyms: ['hi', 'hey'],
      );
      expect(m.partOfSpeech, 'noun');
      expect(m.definitions, ['A greeting.']);
      expect(m.examples, ['Hello there.']);
      expect(m.synonyms, ['hi', 'hey']);
    });

    test('empty lists are valid', () {
      const m = MeaningEntry(
        partOfSpeech: 'verb',
        definitions: [],
        examples: [],
        synonyms: [],
      );
      expect(m.definitions, isEmpty);
      expect(m.examples, isEmpty);
      expect(m.synonyms, isEmpty);
    });
  });

  // =========================================================================
  // WordDefinition
  // =========================================================================
  group('WordDefinition', () {
    test('constructor stores word, phonetic, meanings', () {
      const wd = WordDefinition(
        word: 'hello',
        phonetic: '/həˈloʊ/',
        meanings: [],
      );
      expect(wd.word, 'hello');
      expect(wd.phonetic, '/həˈloʊ/');
      expect(wd.meanings, isEmpty);
    });

    test('phonetic is nullable', () {
      const wd = WordDefinition(word: 'cat', phonetic: null, meanings: []);
      expect(wd.phonetic, isNull);
    });

    test('meanings list is accessible', () {
      const m = MeaningEntry(
        partOfSpeech: 'noun',
        definitions: ['A small domesticated animal.'],
        examples: [],
        synonyms: ['feline'],
      );
      const wd = WordDefinition(word: 'cat', phonetic: '/kæt/', meanings: [m]);
      expect(wd.meanings.length, 1);
      expect(wd.meanings[0].partOfSpeech, 'noun');
    });
  });

  // =========================================================================
  // DictionaryService.lookup()
  // =========================================================================
  group('DictionaryService.lookup()', () {
    test('returns null for empty string', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response('should not be called', 200);
        }),
      );
      final result = await service.lookup('');
      expect(result, isNull);
      service.dispose();
    });

    test('returns null for whitespace-only string', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response('should not be called', 200);
        }),
      );
      final result = await service.lookup('   ');
      expect(result, isNull);
      service.dispose();
    });

    test('returns null when API returns 404', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response('{"title": "No Definitions Found"}', 404);
        }),
      );
      final result = await service.lookup('xyzzy');
      expect(result, isNull);
      service.dispose();
    });

    test('returns null when API returns 500', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response('Internal Server Error', 500);
        }),
      );
      final result = await service.lookup('hello');
      expect(result, isNull);
      service.dispose();
    });

    test('returns null on network exception', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          throw Exception('Network error');
        }),
      );
      final result = await service.lookup('hello');
      expect(result, isNull);
      service.dispose();
    });

    test('returns WordDefinition for valid response', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result, isNotNull);
      expect(result!.word, 'hello');
      service.dispose();
    });

    test('normalises word to lowercase', () async {
      late Uri calledUri;
      final service = DictionaryService(
        client: MockClient((req) async {
          calledUri = req.url;
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      await service.lookup('HELLO');
      expect(calledUri.path, contains('hello'));
      service.dispose();
    });

    test('trims whitespace from word before lookup', () async {
      late Uri calledUri;
      final service = DictionaryService(
        client: MockClient((req) async {
          calledUri = req.url;
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      await service.lookup('  hello  ');
      expect(calledUri.path, endsWith('/hello'));
      service.dispose();
    });

    test('extracts phonetic from first non-empty phonetics entry', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result!.phonetic, '/heh-LOH/');
      service.dispose();
    });

    test('returns both meanings (exclamation + noun)', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result!.meanings.length, 2);
      service.dispose();
    });

    test('first meaning has partOfSpeech exclamation', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result!.meanings[0].partOfSpeech, 'exclamation');
      service.dispose();
    });

    test('limits definitions to 3 per meaning', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      // The sample has 4 definitions but service takes only 3
      expect(result!.meanings[0].definitions.length, lessThanOrEqualTo(3));
      service.dispose();
    });

    test('extracts examples from definitions', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result!.meanings[0].examples, isNotEmpty);
      expect(result.meanings[0].examples[0], contains('Hello'));
      service.dispose();
    });

    test('limits synonyms to 5 max', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(_sampleResponseJson, 200);
        }),
      );
      final result = await service.lookup('hello');
      // Sample has 6 synonyms at definition level — service caps at 5
      expect(result!.meanings[0].synonyms.length, lessThanOrEqualTo(5));
      service.dispose();
    });

    test('filters empty definitions', () async {
      final responseWithEmptyDef = jsonEncode([
        {
          'word': 'test',
          'phonetics': [
            {'text': '/test/'},
          ],
          'meanings': [
            {
              'partOfSpeech': 'noun',
              'definitions': [
                {'definition': '', 'example': null, 'synonyms': []},
                {
                  'definition': 'A procedure to verify something.',
                  'synonyms': [],
                },
              ],
              'synonyms': [],
              'antonyms': [],
            },
          ],
        },
      ]);
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(responseWithEmptyDef, 200);
        }),
      );
      final result = await service.lookup('test');
      // Empty definitions are filtered out
      expect(result!.meanings[0].definitions, isNotEmpty);
      expect(result.meanings[0].definitions.every((d) => d.isNotEmpty), isTrue);
      service.dispose();
    });

    test('returns null when API returns empty list', () async {
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response('[]', 200);
        }),
      );
      final result = await service.lookup('hello');
      expect(result, isNull);
      service.dispose();
    });

    test('handles missing phonetics gracefully', () async {
      final noPhonetics = jsonEncode([
        {
          'word': 'cat',
          'phonetics': [],
          'meanings': [
            {
              'partOfSpeech': 'noun',
              'definitions': [
                {'definition': 'A feline.', 'synonyms': []},
              ],
              'synonyms': [],
              'antonyms': [],
            },
          ],
        },
      ]);
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(noPhonetics, 200);
        }),
      );
      final result = await service.lookup('cat');
      expect(result, isNotNull);
      expect(result!.phonetic, isNull);
      service.dispose();
    });

    test('handles missing meanings gracefully (empty list)', () async {
      final noMeanings = jsonEncode([
        {'word': 'xyz', 'phonetics': [], 'meanings': []},
      ]);
      final service = DictionaryService(
        client: MockClient((_) async {
          return http.Response(noMeanings, 200);
        }),
      );
      final result = await service.lookup('xyz');
      expect(result, isNotNull);
      expect(result!.meanings, isEmpty);
      service.dispose();
    });
  });
}
