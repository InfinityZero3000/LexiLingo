import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 7. Collocation Choice
// ═══════════════════════════════════════════════════════════════
class CollocationChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CollocationChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  String _extractMainWord() => extractQuotedWord(exercise.question);

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = exercise.options ?? [];
    final mainWord = _extractMainWord();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mainWord.isNotEmpty
                ? 'lesson.exercise.collocationPrompt'.tr(
                    namedArgs: {'word': mainWord},
                  )
                : exercise.question,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
              height: 1.3,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'lesson.exercise.collocationInstruction'.tr(),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
          if (mainWord.isNotEmpty) ...[
            // Main verb / key word card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                children: [
                  Text(
                    'lesson.exercise.mainVerb'.tr(),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.primary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mainWord,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          ...options.map((opt) {
            final sel = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseOptionCard(
                text: opt,
                showRadio: true,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (exercise.hint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline,
                    size: 18,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'lesson.exercise.hintLabel'.tr(
                        namedArgs: {'hint': exercise.hint!},
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
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
