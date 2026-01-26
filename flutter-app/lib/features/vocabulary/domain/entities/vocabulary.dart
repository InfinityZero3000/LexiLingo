class Vocabulary {
  final String id;
  final String word;
  final String pronunciation;
  final String definition;
  final String? example;
  final String? translation;
  final String? category;
  final bool isFavorite;
  final DateTime? learnedDate;
  final int masteryLevel;

  Vocabulary({
    required this.id,
    required this.word,
    required this.pronunciation,
    required this.definition,
    this.example,
    this.translation,
    this.category,
    this.isFavorite = false,
    this.learnedDate,
    this.masteryLevel = 0,
  });

  Vocabulary copyWith({
    String? id,
    String? word,
    String? pronunciation,
    String? definition,
    String? example,
    String? translation,
    String? category,
    bool? isFavorite,
    DateTime? learnedDate,
    int? masteryLevel,
  }) {
    return Vocabulary(
      id: id ?? this.id,
      word: word ?? this.word,
      pronunciation: pronunciation ?? this.pronunciation,
      definition: definition ?? this.definition,
      example: example ?? this.example,
      translation: translation ?? this.translation,
      category: category ?? this.category,
      isFavorite: isFavorite ?? this.isFavorite,
      learnedDate: learnedDate ?? this.learnedDate,
      masteryLevel: masteryLevel ?? this.masteryLevel,
    );
  }
}
