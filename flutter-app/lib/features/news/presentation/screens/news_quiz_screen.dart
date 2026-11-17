import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/news_entities.dart';
import '../providers/news_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// News Quiz Screen — comprehension quiz after reading an article.
///
/// Features:
/// - Multiple choice questions (comprehension, vocabulary, grammar)
/// - Immediate answer feedback with explanations
/// - Score summary with XP reward
///
/// Phase 2: News Reading.
class NewsQuizScreen extends StatefulWidget {
  final NewsArticle article;

  const NewsQuizScreen({super.key, required this.article});

  @override
  State<NewsQuizScreen> createState() => _NewsQuizScreenState();
}

class _NewsQuizScreenState extends State<NewsQuizScreen>
    with TickerProviderStateMixin {
  late final AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NewsProvider>().loadQuiz(
        widget.article.id,
        article: widget.article,
      );
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    // Don't resetQuiz here - let the provider keep state for re-entry
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = _cefrColor(widget.article.cefrLevel);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('newsQuiz.title'.tr()),
        leading: IconButton(
          onPressed: () {
            context.read<NewsProvider>().resetQuiz();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: FadeTransition(
          opacity: _fadeController,
          child: Consumer<NewsProvider>(
            builder: (context, provider, _) {
              if (provider.isLoadingQuiz) {
                return const Center(child: LottieLoadingWidget.medium());
              }

              if (provider.currentQuiz == null ||
                  provider.currentQuiz!.questions.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.quiz_outlined,
                        size: 64,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        'newsQuiz.quizNotAvailable'.tr(),
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      OutlinedButton(
                        onPressed: () => provider.loadQuiz(
                          widget.article.id,
                          article: widget.article,
                        ),
                        child: Text('common.retry'.tr()),
                      ),
                    ],
                  ),
                );
              }

              if (provider.quizSubmitted) {
                return _buildResultsView(provider, cefrColor, isDark);
              }

              return _buildQuizView(provider, cefrColor, isDark);
            },
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────
  //  Quiz Questions View
  // ──────────────────────────────────────

  Widget _buildQuizView(NewsProvider provider, Color cefrColor, bool isDark) {
    final quiz = provider.currentQuiz!;

    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              Text(
                '${provider.answers.length}/${quiz.totalQuestions}',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: cefrColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: provider.answers.length / quiz.totalQuestions,
                    backgroundColor: cefrColor.withValues(alpha: 0.1),
                    color: cefrColor,
                    minHeight: 6,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),

        // Questions
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            itemCount: quiz.questions.length,
            itemBuilder: (context, index) {
              return _buildQuestionCard(
                quiz.questions[index],
                provider,
                cefrColor,
                isDark,
              );
            },
          ),
        ),

        // Submit button
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: provider.answers.length == quiz.totalQuestions
                  ? () {
                      // submitQuiz awards the XP, proportional to the score and
                      // under one source_id. Awarding here too sent a second
                      // request with a different source_id, which the backend's
                      // dedup could not recognise as the same quiz.
                      provider.submitQuiz();
                    }
                  : null,
              style: FilledButton.styleFrom(
                backgroundColor: cefrColor,
                disabledBackgroundColor: cefrColor.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                textStyle: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              child: Text('newsQuiz.submitAnswers'.tr()),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildQuestionCard(
    QuizQuestion question,
    NewsProvider provider,
    Color cefrColor,
    bool isDark,
  ) {
    final selectedAnswer = provider.answers[question.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.onGradient.withValues(alpha: 0.05)
            : Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: 0.04),

              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Question type badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 3,
            ),
            decoration: BoxDecoration(
              color: _questionTypeColor(question.type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              question.type.toUpperCase(),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: _questionTypeColor(question.type),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Question text
          Text(
            question.question,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),

          // Options
          ...question.options.asMap().entries.map((entry) {
            final index = entry.key;
            final option = entry.value;
            final isSelected = selectedAnswer == index;

            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: GestureDetector(
                onTap: () => provider.answerQuestion(question.id, index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cefrColor.withValues(alpha: 0.08)
                        : (isDark
                              ? AppColors.onGradient.withValues(alpha: 0.03)
                              : AppColors.grey50),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: isSelected
                          ? cefrColor
                          : (isDark
                                ? AppColors.onGradient.withValues(alpha: 0.08)
                                : Theme.of(context).colorScheme.outlineVariant),

                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Letter badge
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? cefrColor
                              : (isDark
                                    ? AppColors.onGradient.withValues(
                                        alpha: 0.06,
                                      )
                                    : AppColors.grey100),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + index), // A, B, C, D
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: isSelected
                                      ? AppColors.onGradient
                                      : (isDark
                                            ? AppColors.onGradient.withValues(
                                                alpha: 0.54,
                                              )
                                            : Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant),
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Text(
                          option,
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: isSelected
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Results View
  // ──────────────────────────────────────

  Widget _buildResultsView(
    NewsProvider provider,
    Color cefrColor,
    bool isDark,
  ) {
    final score = provider.quizScore;
    final total = provider.quizTotal;
    final percentage = total > 0 ? (score / total * 100).round() : 0;
    final quiz = provider.currentQuiz!;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          const SizedBox(height: 20),

          // Score circle
          Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  cefrColor.withValues(alpha: 0.2),
                  cefrColor.withValues(alpha: 0.05),
                ],
              ),
              border: Border.all(color: cefrColor, width: 4),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '$score/$total',
                  style: TextStyle(
                    fontSize: 36,
                    fontWeight: FontWeight.w800,
                    color: cefrColor,
                  ),
                ),
                Text(
                  '$percentage%',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: cefrColor.withValues(alpha: 0.7),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 20),

          // Result message
          Text(
            _resultMessage(percentage),
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            _resultSubMessage(percentage),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: isDark
                  ? AppColors.onGradient.withValues(alpha: 0.54)
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),

            textAlign: TextAlign.center,
          ),

          // XP reward
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              color: cefrColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: cefrColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, color: cefrColor, size: 24),
                const SizedBox(width: AppSpacing.sm),
                Text(
                  '+${quiz.xpReward} XP',
                  style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                    color: cefrColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: AppSpacing.xxl),

          // Question review
          ...quiz.questions.asMap().entries.map((entry) {
            final q = entry.value;
            final userAnswer = provider.answers[q.id];
            final isCorrect = userAnswer == q.correctIndex;

            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? AppColors.onGradient.withValues(alpha: 0.04)
                    : AppColors.onGradient,

                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: isCorrect
                      ? context.status.success.withValues(alpha: 0.3)
                      : Theme.of(
                          context,
                        ).colorScheme.error.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        isCorrect
                            ? Icons.check_circle_rounded
                            : Icons.cancel_rounded,
                        color: isCorrect
                            ? context.status.success
                            : Theme.of(context).colorScheme.error,

                        size: 20,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          q.question,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  if (!isCorrect) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      'newsQuiz.correct'.tr(
                        namedArgs: {'answer': q.options[q.correctIndex]},
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: context.status.success,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      q.explanation,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.onGradient.withValues(alpha: 0.38)
                            : Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: AppSpacing.xl),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    provider.resetQuiz();
                    provider.loadQuiz(
                      widget.article.id,
                      article: widget.article,
                    );
                  },
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cefrColor,
                    side: BorderSide(color: cefrColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('newsQuiz.retry'.tr()),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  onPressed: () {
                    provider.resetQuiz();
                    Navigator.pop(context);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: cefrColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: Text('newsQuiz.done'.tr()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  // ──────────────────────────────────────
  //  Helpers
  // ──────────────────────────────────────

  Color _cefrColor(String level) {
    switch (level) {
      case 'A1':
        return context.status.success;
      case 'A2':
        return AppColors.greenSuccessSoft;
      case 'B1':
        return context.status.warning;
      case 'B2':
        return AppColors.orange;
      case 'C1':
        return AppColors.deepOrange;
      case 'C2':
        return AppColors.purple;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  Color _questionTypeColor(String type) {
    switch (type) {
      case 'comprehension':
        return Theme.of(context).colorScheme.primary;
      case 'vocabulary':
        return AppColors.purple;
      case 'grammar':
        return AppColors.orange;
      default:
        return Theme.of(context).colorScheme.primary;
    }
  }

  String _resultMessage(int percentage) {
    if (percentage >= 80) return 'newsQuiz.excellentMessage'.tr();
    if (percentage >= 60) return 'newsQuiz.goodJobMessage'.tr();
    if (percentage >= 40) return 'newsQuiz.keepPracticingMessage'.tr();
    return 'newsQuiz.dontGiveUpMessage'.tr();
  }

  String _resultSubMessage(int percentage) {
    if (percentage >= 80) {
      return 'newsQuiz.excellentSub'.tr();
    }
    if (percentage >= 60) {
      return 'newsQuiz.goodJobSub'.tr();
    }
    if (percentage >= 40) {
      return 'newsQuiz.keepPracticingSub'.tr();
    }
    return 'newsQuiz.dontGiveUpSub'.tr();
  }
}
