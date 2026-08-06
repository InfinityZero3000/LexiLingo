import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:lexilingo_app/core/services/sound_service.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import '../../domain/entities/lesson_entity.dart';
import '../providers/learning_provider.dart';
import '../widgets/quiz_widget.dart';
import '../widgets/lesson_content_widget.dart';
import '../widgets/premium_exercise_widgets.dart';
import '../../../voice/presentation/widgets/tts_speed_selector.dart';
import '../../../progress/presentation/providers/streak_provider.dart';
import '../../../progress/presentation/widgets/streak_milestone_overlay.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Learning Session Screen
/// Handles the lesson learning flow with interactive exercises
class LearningSessionScreen extends StatefulWidget {
  final String lessonId;
  final String courseId;

  const LearningSessionScreen({
    super.key,
    required this.lessonId,
    required this.courseId,
  });

  @override
  State<LearningSessionScreen> createState() => _LearningSessionScreenState();
}

class _LearningSessionScreenState extends State<LearningSessionScreen> {
  bool _wasAnswered = false;
  bool _wasCompleted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<LearningProvider>();
      provider.startLesson(widget.courseId, widget.lessonId);
      provider.addListener(_onProviderChange);
    });
  }

  @override
  void dispose() {
    context.read<LearningProvider>().removeListener(_onProviderChange);
    super.dispose();
  }

  void _onProviderChange() {
    final provider = context.read<LearningProvider>();

    // Lesson just completed
    if (!_wasCompleted && provider.isCompleted) {
      _wasCompleted = true;
      SoundService.instance.playComplete();
      return;
    }

    // Answer just submitted (isCurrentAnswered flipped from false → true)
    final nowAnswered = provider.isCurrentAnswered;
    if (!_wasAnswered && nowAnswered) {
      final correct = provider.isCurrentCorrect ?? false;
      if (correct) {
        SoundService.instance.playCorrect();
      } else {
        SoundService.instance.playWrong();
      }
    }

    // Reset tracking when moving to the next exercise
    if (_wasAnswered && !nowAnswered) {
      _wasCompleted = false;
    }
    _wasAnswered = nowAnswered;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldExit = await _showExitDialog(context);
        if (shouldExit == true && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('lesson.sessionTitle'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final shouldExit = await _showExitDialog(context);
              if (shouldExit == true && context.mounted) {
                Navigator.of(context).pop();
              }
            },
          ),
          actions: [
            // TTS Speed Control Button
            const TtsSpeedButton(),
            Consumer<LearningProvider>(
              builder: (context, provider, child) {
                if (provider.currentLesson == null) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text(
                      '${provider.currentExerciseIndex + 1}/${provider.totalExercises}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Consumer<LearningProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return LoadingScreen(message: 'lesson.loadingLesson'.tr());
            }

            if (provider.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      size: 64,
                      color: AppColors.errorBright,
                    ),
                    const SizedBox(height: 16),
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        provider.startLesson(widget.courseId, widget.lessonId);
                      },
                      child: Text('common.retry'.tr()),
                    ),
                  ],
                ),
              );
            }

            if (provider.currentLesson == null) {
              return Center(child: Text('lesson.noLessonData'.tr()));
            }

            // Show completion screen
            if (provider.isCompleted) {
              return _buildCompletionScreen(context, provider);
            }

            // Show current exercise
            return Column(
              children: [
                // Progress bar (thick, rounded — matches template)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: provider.progress,
                      minHeight: 10,
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppColorRoles.primary(
                          Theme.of(context).brightness == Brightness.dark,
                        ),
                      ),
                    ),
                  ),
                ),

                // Mission goal (can-do outcome) — shown only at the start of
                // the lesson so the learner knows what they're working
                // toward, per TBLT pre-task framing.
                if (provider.currentExerciseIndex == 0)
                  _buildOutcomeBanner(context, provider.currentLesson?.outcome),

                // Content
                Expanded(child: _buildExerciseContent(context, provider)),

                // Action buttons
                _buildActionButtons(context, provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildOutcomeBanner(BuildContext context, String? outcome) {
    if (outcome == null || outcome.trim().isEmpty) {
      return const SizedBox.shrink();
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.flag_rounded,
              size: 20,
              color: colorScheme.onPrimaryContainer,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                outcome,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onPrimaryContainer,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildExerciseContent(
    BuildContext context,
    LearningProvider provider,
  ) {
    final exercise = provider.currentExercise;

    if (exercise == null) {
      return Center(child: Text('lesson.noExerciseAvailable'.tr()));
    }

    final uiType = exercise.uiType;
    if (uiType != null) {
      switch (uiType) {
        case 'arrange_the_sentence':
          return ArrangeSentenceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'categorization':
          return CategorizationWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer:
                provider.currentUserAnswer ?? provider.currentDraftAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'cognitive_fluidity':
          return CognitiveFluidityWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'collocation_choice':
          return CollocationChoiceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'dialogue_completion':
          return DialogueCompletionWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer:
                provider.currentUserAnswer ?? provider.currentDraftAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'dictation':
          return DictationWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'fill_in_the_blank':
          return FillBlankWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'grammar_correction':
          return GrammarCorrectionWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'image_based_choice':
          return ImageBasedChoiceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'listen_and_choose':
          return ListeningChoiceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'match_word_to_meaning':
          return MatchWordMeaningWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'multiple_choice':
          return MultipleChoiceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'pronunciation_practice':
          return PronunciationPracticeWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'reading_comprehension':
          return ReadingComprehensionWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'short_writing_answer':
          return ShortWritingAnswerWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'speaking_repeat':
          return SpeakingRepeatWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'translation_choice':
          return TranslationChoiceWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'true_or_false':
          return TrueOrFalseWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'vocabulary_flashcard':
          return VocabularyFlashcardWidget(
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
      }
    }

    switch (exercise.type) {
      case ExerciseType.multipleChoice:
      case ExerciseType.trueFalse:
        return QuizWidget(
          exercise: exercise,
          onAnswer: (answer) => provider.submitAnswer(answer),
          isAnswered: provider.isCurrentAnswered,
          userAnswer: provider.currentUserAnswer,
          isCorrect: provider.isCurrentCorrect,
        );

      case ExerciseType.fillInBlank:
      case ExerciseType.translate:
        return LessonContentWidget(
          exercise: exercise,
          onSubmit: (answer) => provider.submitAnswer(answer),
          isAnswered: provider.isCurrentAnswered,
          isCorrect: provider.isCurrentCorrect,
        );

      default:
        return Center(
          child: Text(
            'lesson.exerciseTypeNotImplemented'.tr(
              namedArgs: {'type': exercise.type.name},
            ),
          ),
        );
    }
  }

  Widget _buildActionButtons(BuildContext context, LearningProvider provider) {
    final answered = provider.isCurrentAnswered;
    final correct = provider.isCurrentCorrect ?? false;
    final canCheckDraft = provider.hasCurrentDraftAnswer;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final disabledColor = theme.colorScheme.surfaceContainerHighest;
    final actionForeground = answered || canCheckDraft
        ? Colors.white
        : AppColorRoles.textMuted(isDark);

    // Button colour: correct=green, wrong=orange, not answered=primary blue
    final checkColor = answered
        ? (correct ? const Color(0xFF2DBD73) : const Color(0xFFFF6B35))
        : primaryColor;

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(top: BorderSide(color: theme.dividerColor, width: 1)),
      ),
      child: Row(
        children: [
          // Skip — always visible, outlined pill
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => provider.skipExercise(),
              icon: const Icon(Icons.skip_next_rounded, size: 18),
              label: Text('common.skip'.tr()),
              style: OutlinedButton.styleFrom(
                foregroundColor: primaryColor,
                side: BorderSide(color: primaryColor, width: 1.5),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
          const SizedBox(width: 12),
          // Check / Continue — filled pill
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: answered
                  ? () => provider.nextExercise()
                  : canCheckDraft
                  ? () => provider.submitCurrentDraftAnswer()
                  : null,
              icon: Icon(
                answered
                    ? (correct
                          ? Icons.check_circle_outline
                          : Icons.arrow_forward_rounded)
                    : Icons.check_circle_outline,
                size: 20,
                color: actionForeground,
              ),
              label: Text(
                answered
                    ? 'lesson.continueButton'.tr()
                    : 'lesson.checkAnswer'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: actionForeground,
                ),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: checkColor,
                disabledBackgroundColor: disabledColor,
                disabledForegroundColor: AppColorRoles.textMuted(isDark),
                foregroundColor: Colors.white,
                elevation: answered ? 2 : 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen(
    BuildContext context,
    LearningProvider provider,
  ) {
    final score = provider.score;
    final total = provider.totalExercises;
    final percentage = (score / total * 100).toInt();

    // Update streak when lesson is completed, then show milestone if reached
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final streakProvider = context.read<StreakProvider>();
      await streakProvider.updateStreak();
      if (!mounted) return;
      if (streakProvider.milestoneJustReached) {
        await StreakMilestoneOverlay.show(
          context,
          streakDays: streakProvider.currentStreak,
          onDismiss: streakProvider.clearMilestone,
        );
      }
    });

    return Stack(
      children: [
        // Confetti animation
        Positioned.fill(
          child: IgnorePointer(
            child: Lottie.asset(
              'animation/Confetti.json',
              fit: BoxFit.cover,
              repeat: false,
              renderCache: RenderCache.raster,
            ),
          ),
        ),

        // Content
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Trophy icon with glow effect
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(scale: value, child: child);
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color:
                            (percentage >= 80
                                    ? AppColors.warning
                                    : AppColors.greenSuccessBright)
                                .withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color:
                                (percentage >= 80
                                        ? AppColors.warning
                                        : AppColors.greenSuccessBright)
                                    .withValues(alpha: 0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    if (percentage >= 80)
                      const LottieAnimationWidget(
                        animation: LottieAnimation.starBurst,
                        width: 120,
                        height: 120,
                        repeat: false,
                      )
                    else
                      AnimatedCheckmark(
                        color: AppColors.greenSuccessBright,
                        size: 80,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // Animated Title
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          percentage >= 80
                              ? Icons.celebration
                              : Icons.auto_awesome,
                          color: percentage >= 80
                              ? AppColors.warning
                              : AppColors.purple,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          percentage >= 80
                              ? 'lesson.excellent'.tr()
                              : 'lesson.wellDone'.tr(),
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          percentage >= 80
                              ? Icons.celebration
                              : Icons.auto_awesome,
                          color: percentage >= 80
                              ? AppColors.warning
                              : AppColors.purple,
                          size: 28,
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'lesson.scoreSummary'.tr(
                        namedArgs: {
                          'score': '$score',
                          'total': '$total',
                          'percentage': '$percentage',
                        },
                      ),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: AppColorRoles.textSecondary(
                          Theme.of(context).brightness == Brightness.dark,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 32),

              // XP earned with animation
              if (provider.xpEarned > 0)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.bounceOut,
                  builder: (context, value, child) {
                    return Transform.scale(scale: value, child: child);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade400, Colors.orange.shade400],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.stars,
                          color: AppColors.surfaceLight,
                          size: 28,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+${provider.xpEarned} XP',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: AppColors.surfaceLight,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              const SizedBox(height: 48),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: AppColors.greenSuccessBright,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: Text(
                    'lesson.continueButton'.tr(),
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              if (percentage < 80)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      provider.restartLesson();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      'lesson.practiceAgain'.tr(),
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _showExitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('lesson.exitLessonTitle'.tr()),
        content: Text('lesson.exitLessonMessage'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: AppColors.errorBright),
            child: Text('lesson.exit'.tr()),
          ),
        ],
      ),
    );
  }
}
