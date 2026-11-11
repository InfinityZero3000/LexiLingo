import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 10. Image Based Choice
// ═══════════════════════════════════════════════════════════════
class ImageBasedChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ImageBasedChoiceWidget({
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
    final imageUrl = exercise.metadata?['image_url'] as String?;
    final hasImageUrl = imageUrl != null && imageUrl.trim().isNotEmpty;

    Widget imagePlaceholder() => Container(
      height: 180,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Icon(Icons.image_outlined, size: 64, color: colors.border),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExerciseBadge('lesson.exercise.imageChoiceLabel'.tr()),
          const SizedBox(height: 16),
          Text(
            exercise.question,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 16),
          // Image area
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: hasImageUrl
                ? Image.network(
                    imageUrl,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => imagePlaceholder(),
                  )
                : imagePlaceholder(),
          ),
          const SizedBox(height: 20),
          // 2x2 grid options
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: options.map((opt) {
              final sel = userAnswer == opt;
              final corr = exercise.correctAnswer == opt;
              return ExerciseOptionCard(
                text: opt,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
                radius: 999,
              );
            }).toList(),
          ),
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
