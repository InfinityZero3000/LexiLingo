import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.speakingTitle'.tr(),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              letterSpacing: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'lesson.exercise.speakingInstruction'.tr(),
            style: TextStyle(
              fontSize: 24,
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
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                CircleAudioButton(
                  text: widget.exercise.question,
                  audioUrl: widget.exercise.audioUrl,
                  size: 40,
                ),
                const SizedBox(height: 14),
                Text(
                  '"${widget.exercise.question}"',
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
                    style: TextStyle(
                      fontSize: 13,
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
          const Spacer(),
          Center(
            child: LessonSpeakingRecorder(
              targetText: widget.exercise.correctAnswer.isNotEmpty
                  ? widget.exercise.correctAnswer
                  : widget.exercise.question,
              isAnswered: widget.isAnswered,
              onApproved: widget.onAnswer,
              onAttempt: widget.onInputChanged,
              primaryColor: colors.primary,
              secondaryTextColor: colors.textSecondary,
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
