import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 15. Reading Comprehension
// ═══════════════════════════════════════════════════════════════
class ReadingComprehensionWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ReadingComprehensionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  // The question contains the passage + "?" question
  // Try to split on the last sentence that ends with "?"
  (String, String) _splitPassageAndQuestion() {
    final q = exercise.question;
    // Find last sentence that looks like a question
    final sentences = q.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 1) {
      final last = sentences.last;
      if (last.trim().endsWith('?')) {
        final passage = sentences.sublist(0, sentences.length - 1).join(' ');
        return (passage.trim(), last.trim());
      }
    }
    // Fallback: whole question is the question, no passage
    return ('', q);
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final (passage, question) = _splitPassageAndQuestion();
    final options = exercise.options ?? [];
    final letters = ['A', 'B', 'C', 'D', 'E'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.readingTitle'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'lesson.exercise.readingInstruction'.tr(),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          if (passage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: colors.border),
              ),
              child: SingleChildScrollView(
                child: Text(
                  passage,
                  style: TextStyle(
                    fontSize: 14,
                    color: colors.textPrimary,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            question,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 16),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final sel = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseOptionCard(
                text: opt,
                label: i < letters.length ? letters[i] : '${i + 1}',
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
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
