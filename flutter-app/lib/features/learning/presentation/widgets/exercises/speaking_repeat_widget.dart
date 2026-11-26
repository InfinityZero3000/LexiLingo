import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

// ═══════════════════════════════════════════════════════════════
// 17. Speaking Repeat
// ═══════════════════════════════════════════════════════════════
class SpeakingRepeatWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;

  /// Reports the best take while the learner is still below the pass mark, so
  /// a session they never pass is still measured instead of discarded.
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const SpeakingRepeatWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<SpeakingRepeatWidget> createState() => _SpeakingRepeatWidgetState();
}

class _SpeakingRepeatWidgetState extends State<SpeakingRepeatWidget> {
  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    return ExerciseScrollBody(
      children: [
        Text(
          'lesson.exercise.speakingTitle'.tr(),
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            fontWeight: FontWeight.w700,
            color: colors.primary,
            letterSpacing: 1.5,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'lesson.exercise.speakingInstruction'.tr(),
          style: Theme.of(context).textTheme.headlineSmall!.copyWith(
            fontWeight: FontWeight.w800,
            color: colors.textPrimary,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        // Sentence card with speaker + translation
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: colors.card,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.border),
          ),
          child: Column(
            children: [
              CircleAudioButton(
                text: speakingTarget(widget.exercise),
                audioUrl: widget.exercise.audioUrl,
                size: 40,
              ),
              const SizedBox(height: 14),
              Text(
                '"${speakingTarget(widget.exercise)}"',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.exercise.explanation != null) ...[
                const SizedBox(height: 8),
                Text(
                  widget.exercise.explanation!,
                  style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                    color: colors.textSecondary,
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
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
