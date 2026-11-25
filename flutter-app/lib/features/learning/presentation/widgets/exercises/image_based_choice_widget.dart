import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, AppSpacing.lg),
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
          if (hasImageUrl) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Image.network(
                cacheWidth: 800,
                imageUrl,
                height: 200,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: 20),
          ],
          for (final opt in options) ...[
            ExerciseOptionCard(
              text: opt,
              isSelected: userAnswer == opt,
              isCorrect: exercise.correctAnswer == opt,
              isAnswered: isAnswered,
              onTap: () => onAnswer(opt),
              radius: AppRadius.pill,
            ),
            const SizedBox(height: 12),
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
