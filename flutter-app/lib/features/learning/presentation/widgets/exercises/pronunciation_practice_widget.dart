import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

// ═══════════════════════════════════════════════════════════════
// 14. Pronunciation Practice
// ═══════════════════════════════════════════════════════════════
class PronunciationPracticeWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;

  /// Reports the best take while the learner is still below the pass mark, so
  /// a session they never pass is still measured instead of discarded.
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const PronunciationPracticeWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<PronunciationPracticeWidget> createState() =>
      _PronunciationPracticeWidgetState();
}

class _PronunciationPracticeWidgetState
    extends State<PronunciationPracticeWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    return ExerciseScrollBody(
      children: [
        Text(
          'lesson.exercise.pronunciationTitle'.tr(),
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'lesson.exercise.pronunciationInstruction'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyMedium!.copyWith(color: colors.textSecondary),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Sentence card with speaker
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.border),
          ),
          child: Row(
            children: [
              CircleAudioButton(
                text: speakingTarget(widget.exercise),
                audioUrl: widget.exercise.audioUrl,
                size: 44,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '"${speakingTarget(widget.exercise)}"',
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (widget.exercise.explanation != null) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.exercise.explanation!,
                        style: Theme.of(context).textTheme.bodySmall!.copyWith(
                          color: colors.textSecondary,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Center(
          child: LessonSpeakingRecorder(
            targetText: speakingTarget(widget.exercise),
            isAnswered: widget.isAnswered,
            onApproved: widget.onAnswer,
            onAttempt: widget.onInputChanged,
            primaryColor: colors.primary,
            secondaryTextColor: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
      ],
    );
  }
}
