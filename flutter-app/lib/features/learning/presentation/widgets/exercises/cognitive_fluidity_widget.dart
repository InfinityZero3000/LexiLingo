import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/match_word_meaning_widget.dart';

// ═══════════════════════════════════════════════════════════════
// 19. Cognitive Fluidity (fast matching — same layout as Match)
// ═══════════════════════════════════════════════════════════════
class CognitiveFluidityWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CognitiveFluidityWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) => MatchWordMeaningWidget(
    exercise: exercise,
    onAnswer: onAnswer,
    onInputChanged: onInputChanged,
    isAnswered: isAnswered,
    userAnswer: userAnswer,
    isCorrect: isCorrect,
  );
}
