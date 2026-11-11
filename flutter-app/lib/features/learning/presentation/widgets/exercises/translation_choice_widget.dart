import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 5. Translation Choice
// ═══════════════════════════════════════════════════════════════
class TranslationChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const TranslationChoiceWidget({
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
    final options = exercise.options ?? [];

    // Extract source sentence (strip instruction prefix)
    String source = exercise.question;
    for (final prefix in [
      'Translate to English:',
      'Choose the translation for:',
      'Choose the correct translation:',
      'Translation of:',
    ]) {
      if (source.contains(prefix)) {
        source = source
            .substring(source.indexOf(prefix) + prefix.length)
            .trim();
        break;
      }
    }
    // Remove surrounding quotes
    // Strip surrounding quotes
    if ((source.startsWith("'") && source.endsWith("'")) ||
        (source.startsWith('"') && source.endsWith('"'))) {
      source = source.substring(1, source.length - 1).trim();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.translationChoiceTitle'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          // Source sentence card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.volume_up_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '"$source"',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                      height: 1.4,
                    ),
                  ),
                ),
                SpeakIconButton(text: source, size: 18, color: colors.primary),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final sel = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseOptionCard(
                text: opt,
                label: '${i + 1}',
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
