import 'word_translation.dart';

class VocabWord {
  final int? id;
  final String? userVocabularyId; // Backend UserVocabulary UUID
  final String word;
  final String definition;
  final bool isLearned;
  final String? pronunciation; // IPA phonetic, e.g. /rɪˈzɪl.jənt/
  final String? audioUrl; // Remote audio URL for TTS playback
  final String? example; // Example sentence
  final String? partOfSpeech; // noun, verb, adjective…
  final List<String>? tags; // Topic tags, e.g. ["business", "travel"]
  final Map<String, dynamic>? translation; // {"vi": "...", "examples": [...]}

  VocabWord({
    this.id,
    this.userVocabularyId,
    required this.word,
    required this.definition,
    this.isLearned = false,
    this.pronunciation,
    this.audioUrl,
    this.example,
    this.partOfSpeech,
    this.tags,
    this.translation,
  });

  String? gloss(String localeCode) =>
      localizedGloss(translation, definition, localeCode);

  String? definitionIn(String localeCode) =>
      localizedDefinition(translation, definition, localeCode);
}
