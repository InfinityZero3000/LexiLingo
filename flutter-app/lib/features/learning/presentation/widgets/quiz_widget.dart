import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import '../../domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/quick_save_selection_area.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';

/// Quiz Widget for Multiple Choice and True/False exercises
class QuizWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const QuizWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.isAnswered = false,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<QuizWidget>
    with SingleTickerProviderStateMixin {
  String? _selectedAnswer;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _selectedAnswer = widget.userAnswer;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(QuizWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnswered && !oldWidget.isAnswered) {
      _animationController.forward();
    }
    if (widget.exercise != oldWidget.exercise) {
      _selectedAnswer = null;
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = AppColorRoles.primary(isDark);
    final palette = ExercisePalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final status = context.status;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Question
          DecoratedBox(
            decoration: BoxDecoration(
              color: palette.card,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 12,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getQuestionTypeLabel(),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
                      color: palette.textMuted,
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
                      padding: const EdgeInsets.all(AppSpacing.md),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
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
                                    .copyWith(color: accentColor),
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

          // Options
          ...widget.exercise.options!.map((option) {
            final isSelected = _selectedAnswer == option;
            final isCorrectAnswer = widget.exercise.correctAnswer == option;
            final showResult = widget.isAnswered;

            Color? backgroundColor;
            Color textColor = palette.textPrimary;
            Color? iconColor;
            IconData? icon;

            if (showResult) {
              if (isCorrectAnswer) {
                backgroundColor = status.successContainer;
                textColor = status.onSuccessContainer;
                iconColor = status.onSuccessContainer;
                icon = Icons.check_circle;
              } else if (isSelected && !isCorrectAnswer) {
                backgroundColor = scheme.errorContainer;
                textColor = scheme.onErrorContainer;
                iconColor = scheme.onErrorContainer;
                icon = Icons.cancel;
              }
            } else if (isSelected) {
              backgroundColor = accentColor.withValues(alpha: 0.14);
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: Semantics(
                button: true,
                enabled: !widget.isAnswered,
                selected: isSelected,
                label: option,
                excludeSemantics: true,
                child: InkWell(
                  onTap: widget.isAnswered
                      ? null
                      : () {
                          setState(() => _selectedAnswer = option);
                          widget.onAnswer(option);
                        },
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    constraints: const BoxConstraints(minHeight: 52),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      color: backgroundColor ?? palette.card,
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      boxShadow: showResult
                          ? null
                          : [
                              BoxShadow(
                                color: palette.shadow,
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            option,
                            style: Theme.of(context).textTheme.bodyLarge!
                                .copyWith(
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: textColor,
                                ),
                          ),
                        ),
                        if (showResult && icon != null)
                          Icon(icon, color: iconColor),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }),

          // Explanation (shown after answering)
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _animation,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: widget.isCorrect!
                      ? status.successContainer
                      : scheme.errorContainer,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
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
                                ? status.onSuccessContainer
                                : scheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.isCorrect!
                                ? 'learning.correct'.tr()
                                : 'vocabQuiz.incorrect'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge!
                                .copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: widget.isCorrect!
                                      ? status.onSuccessContainer
                                      : scheme.onErrorContainer,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      QuickSaveSelectionArea(
                        sourceType: 'course_lesson',
                        sourceReference: widget.exercise.id,
                        contextSentence: widget.exercise.explanation!,
                        child: Text(
                          widget.exercise.explanation!,
                          style: Theme.of(context).textTheme.bodyMedium!
                              .copyWith(
                                height: 1.5,
                                color: widget.isCorrect!
                                    ? status.onSuccessContainer
                                    : scheme.onErrorContainer,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getQuestionTypeLabel() {
    switch (widget.exercise.type) {
      case ExerciseType.multipleChoice:
        return 'learning.exerciseType.multipleChoice'.tr();
      case ExerciseType.trueFalse:
        return 'learning.exerciseType.trueFalse'.tr();
      default:
        return 'learning.exerciseType.question'.tr();
    }
  }
}
