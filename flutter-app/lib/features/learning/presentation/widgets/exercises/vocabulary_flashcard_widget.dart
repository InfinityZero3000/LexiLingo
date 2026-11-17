import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

// ═══════════════════════════════════════════════════════════════
// 13. Vocabulary Flashcard
// ═══════════════════════════════════════════════════════════════
class VocabularyFlashcardWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const VocabularyFlashcardWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<VocabularyFlashcardWidget> createState() =>
      _VocabularyFlashcardWidgetState();
}

class _VocabularyFlashcardWidgetState extends State<VocabularyFlashcardWidget> {
  // Extract the word from question (e.g. "Learn: 'Adventure'" → "Adventure")
  String get _word {
    final quoted = extractQuotedWord(widget.exercise.question);
    if (quoted.isNotEmpty) return quoted;
    final colonIdx = widget.exercise.question.indexOf(':');
    if (colonIdx != -1) {
      return widget.exercise.question.substring(colonIdx + 1).trim();
    }
    return widget.exercise.question;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = widget.exercise.options ?? [];
    final imageUrl = widget.exercise.metadata?['image_url'] as String?;
    final hasImageUrl = imageUrl != null && imageUrl.trim().isNotEmpty;
    final word = _word;

    // If options is just ["Got it!"], show simple flashcard
    if (options.length == 1 && options[0] == 'Got it!') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          20,
          AppSpacing.xl,
          20,
          AppSpacing.lg,
        ),
        child: Column(
          children: [
            // Flashcard
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.xl),
              decoration: BoxDecoration(
                color: colors.card,
                borderRadius: BorderRadius.circular(AppRadius.xl),
                border: Border.all(color: colors.border),
                boxShadow: [
                  BoxShadow(
                    color: colors.shadow,
                    blurRadius: 20,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  CircleAudioButton(text: word, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    word,
                    style: Theme.of(context).textTheme.headlineMedium!.copyWith(
                      fontWeight: FontWeight.w800,
                      color: colors.primary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.exercise.explanation != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.exercise.explanation!,
                      style: Theme.of(context).textTheme.bodyMedium!.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (hasImageUrl) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Image.network(
                        imageUrl,
                        height: 140,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: widget.isAnswered
                  ? null
                  : () => widget.onAnswer('Got it!'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                  horizontal: 40,
                  vertical: AppSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: widget.isAnswered ? kCorrect : colors.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  boxShadow: [
                    BoxShadow(
                      color: colors.primary.withValues(alpha: 0.3),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Text(
                  'lesson.exercise.understood'.tr(),
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Vocab MCQ variant: word + "What is the meaning?" + options
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.lg, 20, AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flashcard header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(AppRadius.xl),
              border: Border.all(color: colors.border),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [CircleAudioButton(text: word, size: 36)],
                ),
                const SizedBox(height: 10),
                Text(
                  word,
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: colors.primary,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (hasImageUrl) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: Image.network(
                      imageUrl,
                      height: 120,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'lesson.exercise.meaningQuestion'.tr(),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final sel = widget.userAnswer == opt;
            final corr = widget.exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: ExerciseOptionCard(
                text: opt,
                label: '${i + 1}',
                labelOnRight: true,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: widget.isAnswered,
                onTap: () => widget.onAnswer(opt),
              ),
            );
          }),
          if (widget.isAnswered) ...[
            const SizedBox(height: 16),
            ExerciseExplanationCard(
              explanation: widget.exercise.explanation,
              isCorrect: widget.isCorrect ?? false,
              correctAnswer: widget.exercise.correctAnswer,
            ),
          ],
        ],
      ),
    );
  }
}
