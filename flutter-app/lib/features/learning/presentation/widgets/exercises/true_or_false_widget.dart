import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 1. True or False
// ═══════════════════════════════════════════════════════════════
class TrueOrFalseWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const TrueOrFalseWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = ['True', 'False'];
    final letters = ['A', 'B'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExerciseBadge('lesson.exercise.trueFalseLabel'.tr()),
          const SizedBox(height: 20),
          // Question card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Text(
              exercise.question,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final sel = userAnswer == opt;
            final correct =
                exercise.correctAnswer.toLowerCase() == opt.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseOptionCard(
                text: opt,
                label: letters[i],
                isSelected: sel,
                isCorrect: correct,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
                radius: 20,
              ),
            );
          }),
          if (isAnswered) ...[
            const SizedBox(height: 16),
            ExerciseExplanationCard(
              explanation: exercise.explanation,
              isCorrect: isCorrect ?? false,
              correctAnswer: exercise.correctAnswer,
            ),
          ],
        ],
      ),
    );
  }
}
