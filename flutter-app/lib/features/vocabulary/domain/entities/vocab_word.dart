class VocabWord {
  final int? id;
  final String word;
  final String definition;
  final bool isLearned;

  VocabWord({this.id, required this.word, required this.definition, this.isLearned = false});
}
