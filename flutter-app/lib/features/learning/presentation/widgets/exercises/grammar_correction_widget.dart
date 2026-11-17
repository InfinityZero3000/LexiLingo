import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

// ═══════════════════════════════════════════════════════════════
// 9. Grammar Correction
// ═══════════════════════════════════════════════════════════════
class GrammarCorrectionWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const GrammarCorrectionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  String _extractError() {
    final quoted = extractQuotedWord(exercise.question);
    if (quoted.isNotEmpty) return quoted;
    final colonIdx = exercise.question.indexOf(':');
    if (colonIdx != -1) {
      return exercise.question.substring(colonIdx + 1).trim();
    }
    return exercise.question;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = exercise.options ?? [];
    final errorSentence = _extractError();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.grammarCorrectionTitle'.tr(),
            style: Theme.of(context).textTheme.titleLarge!.copyWith(
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'lesson.exercise.grammarCorrectionInstruction'.tr(),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium!.copyWith(color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
          // Error sentence card
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: kError.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(
                color: kError.withValues(alpha: 0.3),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: colors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.info_outline,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'lesson.exercise.incorrectSentence'.tr(),
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.primary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"$errorSentence"',
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (options.isNotEmpty) ...[
            ...List.generate(options.length, (i) {
              final opt = options[i];
              final sel = userAnswer == opt;
              final corr = exercise.correctAnswer == opt;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.md),
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
          ] else ...[
            _GrammarTextInput(
              exercise: exercise,
              onAnswer: onAnswer,
              isAnswered: isAnswered,
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

class _GrammarTextInput extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  const _GrammarTextInput({
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
  });

  @override
  State<_GrammarTextInput> createState() => _GrammarTextInputState();
}

class _GrammarTextInputState extends State<_GrammarTextInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    return Column(
      children: [
        TextField(
          controller: _ctrl,
          enabled: !widget.isAnswered,
          decoration: InputDecoration(
            hintText: 'lesson.exercise.correctSentenceHint'.tr(),
            filled: true,
            fillColor: colors.card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(color: colors.border),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              borderSide: BorderSide(color: colors.primary, width: 2),
            ),
          ),
        ),
        if (!widget.isAnswered) ...[
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: () {
              if (_ctrl.text.trim().isNotEmpty) {
                widget.onAnswer(_ctrl.text.trim());
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              padding: const EdgeInsets.symmetric(
                vertical: 14,
                horizontal: AppSpacing.xxl,
              ),
            ),
            child: Text(
              'common.confirm'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ],
    );
  }
}
