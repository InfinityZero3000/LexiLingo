import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';

class VocabWordModel extends VocabWord {
  VocabWordModel({
    int? id,
    required String word,
    required String definition,
    bool isLearned = false,
  }) : super(
          id: id,
          word: word,
          definition: definition,
          isLearned: isLearned,
        );

  // Convert from JSON to Model
  factory VocabWordModel.fromJson(Map<String, dynamic> json) {
    return VocabWordModel(
      id: json['id'] as int?,
      word: json['word'] as String,
      definition: json['definition'] as String,
      isLearned: (json['isLearned'] as int?) == 1,
    );
  }

  // Convert from Model to JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'word': word,
      'definition': definition,
      'isLearned': isLearned ? 1 : 0,
    };
  }

  // Convert from Entity to Model
  factory VocabWordModel.fromEntity(VocabWord entity) {
    return VocabWordModel(
      id: entity.id,
      word: entity.word,
      definition: entity.definition,
      isLearned: entity.isLearned,
    );
  }
}
