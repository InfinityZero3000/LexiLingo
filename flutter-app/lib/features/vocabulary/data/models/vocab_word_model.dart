import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

class VocabWordModel extends VocabWord {
  VocabWordModel({
    super.id,
    required super.word,
    required super.definition,
    super.isLearned,
    super.pronunciation,
    super.audioUrl,
    super.example,
    super.partOfSpeech,
  });

  factory VocabWordModel.fromJson(Map<String, dynamic> json) {
    return VocabWordModel(
      id: json['id'] as int?,
      word: json['word'] as String,
      definition: json['definition'] as String,
      isLearned: json['isLearned'] == 1 || json['isLearned'] == true,
      pronunciation: json['pronunciation'] as String?,
      audioUrl: json['audioUrl'] as String?,
      example: json['example'] as String?,
      partOfSpeech: json['partOfSpeech'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'word': word,
      'definition': definition,
      'isLearned': isLearned ? 1 : 0,
      if (pronunciation != null) 'pronunciation': pronunciation,
      if (audioUrl != null) 'audioUrl': audioUrl,
      if (example != null) 'example': example,
      if (partOfSpeech != null) 'partOfSpeech': partOfSpeech,
    };
  }

  factory VocabWordModel.fromEntity(VocabWord entity) {
    return VocabWordModel(
      id: entity.id,
      word: entity.word,
      definition: entity.definition,
      isLearned: entity.isLearned,
      pronunciation: entity.pronunciation,
      audioUrl: entity.audioUrl,
      example: entity.example,
      partOfSpeech: entity.partOfSpeech,
    );
  }
}
