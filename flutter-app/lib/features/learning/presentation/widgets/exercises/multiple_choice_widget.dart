import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 2. Multiple Choice
// ═══════════════════════════════════════════════════════════════
class MultipleChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const MultipleChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  // Renders question; replaces {blank} or ___ with a continuous underline
  Widget _buildQuestion(ExercisePalette colors) {
    final q = exercise.question;
    const style = TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      height: 1.4,
    );

    String? before, after;
    if (q.contains('{blank}')) {
      final parts = q.split('{blank}');
      before = parts[0];
      after = parts.length > 1 ? parts[1] : '';
    } else {
      final match = RegExp(r'_{2,}').firstMatch(q);
      if (match != null) {
        before = q.substring(0, match.start);
        after = q.substring(match.end);
      }
    }

    if (before == null) {
      return Text(q, style: style.copyWith(color: colors.textPrimary));
    }

    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (before.isNotEmpty)
          Text(before, style: style.copyWith(color: colors.textPrimary)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 6),
          width: 80,
          height: 28,
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colors.primary, width: 2.5),
            ),
          ),
        ),
        if (after != null && after.isNotEmpty)
          Text(after, style: style.copyWith(color: colors.textPrimary)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = exercise.options ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExerciseBadge('lesson.exercise.multipleChoiceLabel'.tr()),
          const SizedBox(height: 20),
          // Question
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _buildQuestion(colors)),
              const SizedBox(width: 8),
              SpeakIconButton(
                text: exercise.question,
                size: 22,
                color: colors.primary,
              ),
            ],
          ),
          const SizedBox(height: 24),
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
