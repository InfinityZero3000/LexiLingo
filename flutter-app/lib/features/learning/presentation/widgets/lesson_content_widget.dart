import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Lesson Content Widget for Fill in Blank and Translation exercises
class LessonContentWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onSubmit;
  final bool isAnswered;
  final bool? isCorrect;

  const LessonContentWidget({
    super.key,
    required this.exercise,
    required this.onSubmit,
    this.isAnswered = false,
    this.isCorrect,
  });

  @override
  State<LessonContentWidget> createState() => _LessonContentWidgetState();
}

class _LessonContentWidgetState extends State<LessonContentWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(LessonContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercise != oldWidget.exercise) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppColorRoles.primary(isDark);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Question Card
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getExerciseTypeLabel(),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: QuickSaveSelectionArea(
                          sourceType: 'course_lesson',
                          sourceReference: widget.exercise.id,
                          contextSentence: widget.exercise.question,
                          child: Text(
                            widget.exercise.question,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // TTS Speak Button for question
                      SpeakIconButton(
                        text: widget.exercise.question,
                        size: 24,
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),

                  // Show hint if available
                  if (widget.exercise.hint != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            size: 20,
                            color: accentColor,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: QuickSaveSelectionArea(
                              sourceType: 'course_lesson',
                              sourceReference: widget.exercise.id,
                              contextSentence: widget.exercise.hint!,
                              child: Text(
                                widget.exercise.hint!,
                                style: Theme.of(context).textTheme.bodyMedium!
                                    .copyWith(color: accentColor, height: 1.4),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Answer Input Field
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !widget.isAnswered,
            maxLines: widget.exercise.type == ExerciseType.translate ? 3 : 1,
            decoration: InputDecoration(
              hintText: widget.exercise.type == ExerciseType.translate
                  ? 'learning.hintTranslation'.tr()
                  : 'learning.hintFillBlank'.tr(),
              filled: true,
              fillColor: widget.isAnswered
                  ? (widget.isCorrect!
                            ? context.status.success
                            : Theme.of(context).colorScheme.error)
                        .withValues(alpha: 0.1)
                  : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey[300]!, width: 2),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.isAnswered
                      ? (widget.isCorrect!
                            ? context.status.success
                            : Theme.of(context).colorScheme.error)
                      : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              suffixIcon: widget.isAnswered
                  ? Icon(
                      widget.isCorrect! ? Icons.check_circle : Icons.cancel,
                      color: widget.isCorrect!
                          ? context.status.success
                          : Theme.of(context).colorScheme.error,
                    )
                  : null,
            ),
            style: Theme.of(context).textTheme.bodyLarge!,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (value) {
              if (!widget.isAnswered && value.trim().isNotEmpty) {
                widget.onSubmit(value.trim());
              }
            },
          ),

          const SizedBox(height: 16),

          // Submit Button
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                final answer = _controller.text.trim();
                if (answer.isNotEmpty) {
                  widget.onSubmit(answer);
                  _focusNode.unfocus();
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'learning.checkAnswer'.tr(),
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.bold),
              ),
            ),

          // Result and Explanation
          if (widget.isAnswered) ...[
            const SizedBox(height: 24),
            Card(
              color: widget.isCorrect!
                  ? Colors.green.withValues(alpha: 0.1)
                  : AppColors.orange.withValues(alpha: 0.1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: widget.isCorrect!
                      ? context.status.success
                      : AppColors.orange,
                  width: 1,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          widget.isCorrect!
                              ? Icons.check_circle
                              : Icons.info_outline,
                          color: widget.isCorrect!
                              ? context.status.success
                              : AppColors.orange,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          widget.isCorrect!
                              ? 'learning.correct'.tr()
                              : 'learning.notQuite'.tr(),
                          style: Theme.of(context).textTheme.bodyLarge!
                              .copyWith(
                                fontWeight: FontWeight.bold,
                                color: widget.isCorrect!
                                    ? context.status.success
                                    : AppColors.orange,
                              ),
                        ),
                      ],
                    ),

                    if (!widget.isCorrect!) ...[
                      const SizedBox(height: 12),
                      Text(
                        'learning.correctAnswer'.tr(),
                        style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      QuickSaveSelectionArea(
                        sourceType: 'course_lesson',
                        sourceReference: widget.exercise.id,
                        contextSentence: widget.exercise.correctAnswer,
                        child: Text(
                          widget.exercise.correctAnswer,
                          style: Theme.of(context).textTheme.bodyLarge!
                              .copyWith(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],

                    if (widget.exercise.explanation != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      QuickSaveSelectionArea(
                        sourceType: 'course_lesson',
                        sourceReference: widget.exercise.id,
                        contextSentence: widget.exercise.explanation!,
                        child: Text(
                          widget.exercise.explanation!,
                          style: Theme.of(
                            context,
                          ).textTheme.bodyMedium!.copyWith(height: 1.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getExerciseTypeLabel() {
    switch (widget.exercise.type) {
      case ExerciseType.fillInBlank:
        return 'learning.exerciseType.fillBlank'.tr();
      case ExerciseType.translate:
        return 'learning.exerciseType.translation'.tr();
      default:
        return 'learning.exerciseType.exercise'.tr();
    }
  }
}
