import 'package:lexilingo_app/features/notifications/presentation/widgets/push_permission_card.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/locale_keys.g.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:lexilingo_app/core/services/sound_service.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import '../../domain/entities/lesson_complete.dart';
import '../../domain/entities/lesson_entity.dart';
import '../providers/learning_provider.dart';
import '../widgets/quiz_widget.dart';
import '../widgets/lesson_hearts_row.dart';
import '../widgets/out_of_hearts_sheet.dart';
import '../../../gamification/presentation/providers/gamification_provider.dart';
import '../widgets/lesson_content_widget.dart';
import '../widgets/premium_exercise_widgets.dart';
import '../../../voice/presentation/widgets/tts_speed_selector.dart';
import '../../../progress/presentation/providers/streak_provider.dart';
import '../../../progress/presentation/widgets/streak_milestone_overlay.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
  LearningProvider? _provider;
  bool _heartsSheetOpen = false;
  int _seenHeartsPrompts = 0;
  bool _streakRecorded = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = _provider = context.read<LearningProvider>();
      provider.startLesson(widget.courseId, widget.lessonId);
      provider.addListener(_onProviderChange);
    });
  }

  @override
  void dispose() {
    _provider?.removeListener(_onProviderChange);
    super.dispose();
  }

  Future<void> _showHeartsSheet() async {
    if (_heartsSheetOpen || !mounted) return;
    _heartsSheetOpen = true;
    try {
      final learning = context.read<LearningProvider>();
      final gamification = context.read<GamificationProvider>();
      try {
        await gamification.prepareHeartRefill();
      } catch (_) {}
      if (!mounted) return;
      final choice = await showOutOfHeartsSheet(
        context,
        refillPrice: gamification.heartRefillItem?.priceGems,
        gems: gamification.gems,
        onRefill: () async {
          final ok = await gamification.refillLessonHearts();
          if (ok) learning.heartsRefilled();
          return ok;
        },
      );
      if (!mounted) return;
      switch (choice) {
        case OutOfHeartsChoice.refilled:
          if (learning.isCurrentAnswered) learning.nextExercise();
        case OutOfHeartsChoice.restart:
          await learning.restartLesson();
        case OutOfHeartsChoice.leave:
          Navigator.of(context).pop();
        case null:
          break;
      }
    } finally {
      _heartsSheetOpen = false;
    }
  }

  bool _blockedByHearts(LearningProvider provider) {
    final lastQuestion =
        provider.currentExerciseIndex >= provider.totalExercises - 1;
    if (!provider.isOutOfHearts || lastQuestion) return false;
    _showHeartsSheet();
    return true;
  }

  void _onProviderChange() {
    final provider = context.read<LearningProvider>();

    if (provider.outOfHeartsPromptCount != _seenHeartsPrompts) {
      _seenHeartsPrompts = provider.outOfHeartsPromptCount;
      WidgetsBinding.instance.addPostFrameCallback((_) => _showHeartsSheet());
    }

    if (!provider.isCompleted) {
      _wasCompleted = false;
      _streakRecorded = false;
    }

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
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Center(
                    child: Text(
                      '${(provider.currentExerciseIndex + 1).clamp(1, provider.totalExercises)}/${provider.totalExercises}',
                      style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: ContentWidth(
          maxWidth: ContentWidth.reading,
          child: Consumer<LearningProvider>(
            builder: (context, provider, child) {
              if (provider.isLoading) {
                return LoadingScreen(message: 'lesson.loadingLesson'.tr());
              }

              if (provider.error != null) {
                return _buildErrorState(context, provider);
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
                    child: Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            child: LinearProgressIndicator(
                              value: provider.progress,
                              minHeight: 10,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.surfaceContainerHighest,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                AppColorRoles.primary(
                                  Theme.of(context).brightness ==
                                      Brightness.dark,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        LessonHeartsRow(lives: provider.livesRemaining),
                      ],
                    ),
                  ),

                  _buildPhaseIndicator(
                    context,
                    provider.currentExercise?.phase,
                  ),

                  // Mission goal (can-do outcome) — shown only at the start of
                  // the lesson so the learner knows what they're working
                  // toward, per TBLT pre-task framing.
                  if (provider.currentExerciseIndex == 0)
                    _buildOutcomeBanner(
                      context,
                      provider.currentLesson?.outcome,
                    ),

                  // Content
                  Expanded(child: _buildExerciseContent(context, provider)),

                  // Action buttons
                  _buildActionButtons(context, provider),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context, LearningProvider provider) {
    final theme = Theme.of(context);
    final locked = provider.isLessonLocked;
    final contentGap = provider.isContentUnavailable;
    final terminal = locked || contentGap;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xxl,
          vertical: AppSpacing.xl,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: terminal
                    ? theme.colorScheme.secondaryContainer
                    : theme.colorScheme.errorContainer,
              ),
              child: Icon(
                locked
                    ? Icons.lock_outline_rounded
                    : contentGap
                    ? Icons.hourglass_empty_rounded
                    : Icons.error_outline_rounded,
                size: 44,
                color: terminal
                    ? theme.colorScheme.onSecondaryContainer
                    : theme.colorScheme.onErrorContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              locked
                  ? 'lesson.lockedTitle'.tr()
                  : contentGap
                  ? 'lesson.contentUnavailableTitle'.tr()
                  : 'common.error'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              locked
                  ? 'lesson.lockedMessage'.tr()
                  : contentGap
                  ? 'lesson.contentUnavailableMessage'.tr()
                  : provider.error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 28),
            if (terminal)
              FilledButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.back'.tr()),
              )
            else ...[
              FilledButton(
                onPressed: () =>
                    provider.startLesson(widget.courseId, widget.lessonId),
                child: Text('common.retry'.tr()),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text('common.back'.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhaseIndicator(BuildContext context, String? phase) {
    final key = switch (phase) {
      'pre_task' => 'lesson.phasePreTask',
      'task_cycle' => 'lesson.phaseTaskCycle',
      'language_focus' => 'lesson.phaseLanguageFocus',
      _ => null,
    };
    if (key == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Semantics(
          label: key.tr(),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Text(
              key.tr(),
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colorScheme.onSecondaryContainer,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
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
      padding: const EdgeInsets.fromLTRB(20, 0, 20, AppSpacing.md),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(AppRadius.md),
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
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer:
                provider.currentUserAnswer ?? provider.currentDraftAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'categorization':
          return CategorizationWidget(
            key: ValueKey(exercise.id),
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
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer:
                provider.currentUserAnswer ?? provider.currentDraftAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'collocation_choice':
          return CollocationChoiceWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'dialogue_completion':
          return DialogueCompletionWidget(
            key: ValueKey(exercise.id),
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
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'fill_in_the_blank':
          return FillBlankWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'grammar_correction':
          return GrammarCorrectionWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'image_based_choice':
          return ImageBasedChoiceWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'listen_and_choose':
          return ListeningChoiceWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'match_word_to_meaning':
          return MatchWordMeaningWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer:
                provider.currentUserAnswer ?? provider.currentDraftAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'multiple_choice':
          return MultipleChoiceWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'pronunciation_practice':
          return PronunciationPracticeWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'reading_comprehension':
          return ReadingComprehensionWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'short_writing_answer':
          return ShortWritingAnswerWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'speaking_repeat':
          return SpeakingRepeatWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            onInputChanged: provider.updateDraftAnswer,
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'translation_choice':
          return TranslationChoiceWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'true_or_false':
          return TrueOrFalseWidget(
            key: ValueKey(exercise.id),
            exercise: exercise,
            onAnswer: (answer) => provider.submitAnswer(answer),
            isAnswered: provider.isCurrentAnswered,
            userAnswer: provider.currentUserAnswer,
            isCorrect: provider.isCurrentCorrect,
          );
        case 'vocabulary_flashcard':
          return VocabularyFlashcardWidget(
            key: ValueKey(exercise.id),
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
          key: ValueKey(exercise.id),
          exercise: exercise,
          onAnswer: (answer) => provider.submitAnswer(answer),
          isAnswered: provider.isCurrentAnswered,
          userAnswer: provider.currentUserAnswer,
          isCorrect: provider.isCurrentCorrect,
        );

      case ExerciseType.fillInBlank:
      case ExerciseType.translate:
        return LessonContentWidget(
          key: ValueKey(exercise.id),
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
    final actionForeground = canCheckDraft && !answered
        ? AppColors.textInverted
        : AppColorRoles.textMuted(isDark);

    // Button colour: correct=green, wrong=orange, not answered=primary blue
    final checkColor = answered
        ? (correct ? context.status.success : context.status.warning)
        : primaryColor;
    final checkForeground = answered
        ? (correct ? context.status.onSuccess : context.status.onWarning)
        : actionForeground;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        border: Border(
          top: BorderSide(
            color: theme.dividerColor,
            width: AppBorderWidth.hairline,
          ),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, AppSpacing.md, 20, 20),
          child: Row(
            children: [
              // Skip — always visible, outlined pill
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    if (!_blockedByHearts(provider)) provider.skipExercise();
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: primaryColor,
                    side: BorderSide(
                      color: primaryColor,
                      width: AppBorderWidth.regular,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                  child: Text('common.skip'.tr()),
                ),
              ),
              const SizedBox(width: 12),
              // Check / Continue — filled pill
              Expanded(
                flex: 2,
                child: ElevatedButton.icon(
                  onPressed: answered
                      ? () {
                          if (!_blockedByHearts(provider)) {
                            provider.nextExercise();
                          }
                        }
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
                    color: checkForeground,
                  ),
                  label: Text(
                    answered
                        ? 'lesson.continueButton'.tr()
                        : 'lesson.checkAnswer'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                      color: checkForeground,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: checkColor,
                    disabledBackgroundColor: disabledColor,
                    disabledForegroundColor: AppColorRoles.textMuted(isDark),
                    foregroundColor: checkForeground,
                    elevation: answered ? 2 : 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _recordStreak() {
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
  }

  Widget _buildCompletionScreen(
    BuildContext context,
    LearningProvider provider,
  ) {
    final score = provider.score;
    final total = provider.totalExercises;
    final percentage = total == 0 ? 0 : (score / total * 100).toInt();
    final saving = provider.isCompleting;
    final passMark =
        provider.lessonResult?.passThreshold ?? kDefaultLessonPassMark;
    final passed = provider.lessonResult?.passed ?? percentage >= passMark;
    final excellent = passed && percentage >= kDefaultLessonPassMark;
    final pending = saving && provider.lessonResult == null;

    if (!_streakRecorded) {
      _streakRecorded = true;
      _recordStreak();
    }

    return Stack(
      children: [
        if (passed && !pending)
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
        LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: constraints.maxHeight - AppSpacing.xl * 2,
              ),
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
                                (!passed || excellent
                                        ? context.status.warning
                                        : context.status.success)
                                    .withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (!passed || excellent
                                            ? context.status.warning
                                            : context.status.success)
                                        .withValues(alpha: 0.3),
                                blurRadius: 20,
                                spreadRadius: 10,
                              ),
                            ],
                          ),
                        ),
                        if (pending)
                          const SizedBox(
                            width: 56,
                            height: 56,
                            child: CircularProgressIndicator(),
                          )
                        else if (!passed)
                          Icon(
                            Icons.replay_rounded,
                            color: context.status.warning,
                            size: 72,
                          )
                        else if (excellent)
                          const LottieAnimationWidget(
                            animation: LottieAnimation.starBurst,
                            width: 120,
                            height: 120,
                            repeat: false,
                          )
                        else
                          AnimatedCheckmark(
                            color: context.status.success,
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
                        if (pending)
                          const SizedBox.shrink()
                        else if (!passed)
                          Text(
                            'lesson.notPassedTitle'.tr(),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.headlineMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                          )
                        else
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                excellent
                                    ? Icons.celebration
                                    : Icons.auto_awesome,
                                color: excellent
                                    ? context.status.warning
                                    : AppColors.purple,
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  excellent
                                      ? 'lesson.excellent'.tr()
                                      : 'lesson.wellDone'.tr(),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Icon(
                                excellent
                                    ? Icons.celebration
                                    : Icons.auto_awesome,
                                color: excellent
                                    ? context.status.warning
                                    : AppColors.purple,
                                size: 28,
                              ),
                            ],
                          ),
                        const SizedBox(height: 12),
                        Text(
                          textAlign: TextAlign.center,
                          'lesson.scoreSummary'.tr(
                            namedArgs: {
                              'score': '$score',
                              'total': '$total',
                              'percentage': '$percentage',
                            },
                          ),
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(
                                color: AppColorRoles.textSecondary(
                                  Theme.of(context).brightness ==
                                      Brightness.dark,
                                ),
                              ),
                        ),
                        if (!passed && !pending) ...[
                          const SizedBox(height: 4),
                          Text(
                            'lesson.passMarkHint'.tr(
                              namedArgs: {'passMark': '$passMark'},
                            ),
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),

                  if (provider.completionFailed) ...[
                    Text(
                      'lesson.resultNotSavedTitle'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'lesson.resultNotSavedMessage'.tr(),
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: saving ? null : provider.retryCompletion,
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text('common.retry'.tr()),
                    ),
                  ] else if ((provider.lessonResult?.totalXpEarned ?? 0) > 0)
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.bounceOut,
                      builder: (context, value, child) {
                        return Transform.scale(scale: value, child: child);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xl,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [context.status.warning, AppColors.orange],
                          ),
                          borderRadius: BorderRadius.circular(AppRadius.xl),
                          boxShadow: [
                            BoxShadow(
                              color: context.status.warning.withValues(
                                alpha: 0.4,
                              ),
                              blurRadius: 20,
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
                              '+${provider.lessonResult!.totalXpEarned} XP',
                              style: Theme.of(context).textTheme.headlineSmall!
                                  .copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.surfaceLight,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  const SizedBox(height: 24),
                  const PushPermissionCard(),
                  const SizedBox(height: 24),

                  // Action buttons
                  if (!passed) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saving ? null : provider.restartLesson,
                        icon: const Icon(Icons.replay_rounded),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        label: Text(
                          'lesson.practiceAgain'.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context, true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        child: Text(
                          'lesson.continueButton'.tr(),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ] else if (provider.lessonResult?.nextLessonUnlocked !=
                      null) ...[
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saving
                            ? null
                            : () => Navigator.pushReplacement(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => LearningSessionScreen(
                                    lessonId: provider
                                        .lessonResult!
                                        .nextLessonUnlocked!,
                                    courseId: widget.courseId,
                                  ),
                                ),
                              ),
                        icon: const Icon(Icons.arrow_forward),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          backgroundColor: context.status.success,
                          foregroundColor: context.status.onSuccess,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        label: Text(
                          LocaleKeys.lesson_nextLesson.tr(),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context, true),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        child: Text(
                          'lesson.continueButton'.tr(),
                          style: const TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: saving
                            ? null
                            : () => Navigator.pop(context, true),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          backgroundColor: context.status.success,
                          foregroundColor: context.status.onSuccess,
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                        child: Text(
                          'lesson.continueButton'.tr(),
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),

                  const SizedBox(height: 12),

                  if (passed && percentage < kDefaultLessonPassMark)
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton(
                        onPressed: saving ? null : provider.restartLesson,
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.lg,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
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
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('lesson.exit'.tr()),
          ),
        ],
      ),
    );
  }
}
