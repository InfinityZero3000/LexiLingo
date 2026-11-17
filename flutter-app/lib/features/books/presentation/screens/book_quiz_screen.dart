import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/book_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Comprehension quiz screen for a book chapter.
///
/// Loads quiz questions from the provider, lets user answer one at a time,
/// then shows score + XP earned on completion.
///
/// Phase 5: Book Reading — skill: gamification.
class BookQuizScreen extends StatefulWidget {
  final int chapter;

  const BookQuizScreen({super.key, required this.chapter});

  @override
  State<BookQuizScreen> createState() => _BookQuizScreenState();
}

class _BookQuizScreenState extends State<BookQuizScreen> {
  int _currentQuestion = 0;
  int? _selectedAnswer;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<BookProvider>().loadChapterQuiz(widget.chapter);
    });
  }

  void _selectAnswer(int index) {
    if (_answered) return;
    setState(() {
      _selectedAnswer = index;
      _answered = true;
    });

    final provider = context.read<BookProvider>();
    provider.submitQuizAnswer(_currentQuestion, index);
  }

  void _nextQuestion(BookProvider provider) {
    final quiz = provider.currentQuiz;
    if (quiz == null) return;

    if (_currentQuestion < quiz.questions.length - 1) {
      setState(() {
        _currentQuestion++;
        _selectedAnswer = null;
        _answered = false;
      });
    } else {
      provider.completeQuiz();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text(
          'books.chapterQuizTitle'.tr(
            namedArgs: {'chapter': '${widget.chapter}'},
          ),
          style: Theme.of(
            context,
          ).textTheme.sectionTitle?.copyWith(fontWeight: FontWeight.w700),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: Consumer<BookProvider>(
          builder: (context, provider, _) {
            if (provider.isLoading) {
              return const Center(child: LottieLoadingWidget.medium());
            }

            if (provider.quizCompleted) {
              return _buildResultScreen(context, provider, isDark);
            }

            final quiz = provider.currentQuiz;
            if (quiz == null || quiz.questions.isEmpty) {
              return Center(
                child: Text(
                  'books.quizNotAvailable'.tr(),
                  style: TextStyle(
                    color: isDark
                        ? Colors.white54
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }

            final question = quiz.questions[_currentQuestion];
            return _buildQuestionView(
              context,
              provider,
              question,
              quiz,
              isDark,
            );
          },
        ),
      ),
    );
  }

  Widget _buildQuestionView(
    BuildContext context,
    BookProvider provider,
    dynamic question,
    dynamic quiz,
    bool isDark,
  ) {
    final accentColor = AppColorRoles.primary(isDark);
    final total = quiz.questions.length;
    final progress = (_currentQuestion + 1) / total;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Progress
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 6,
                    backgroundColor: isDark
                        ? Colors.white12
                        : AppColors.grey200,
                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Text(
                '${_currentQuestion + 1}/$total',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: isDark
                      ? Colors.white54
                      : Theme.of(context).colorScheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Question, options and explanation scroll; the action stays put.
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Question
                  Text(
                    question.question,
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.w700,
                      height: 1.45,
                      color: isDark
                          ? AppColors.onGradient
                          : Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xl),

                  // Options
                  ...question.options.asMap().entries.map((entry) {
                    final i = entry.key;
                    final option = entry.value as String;
                    return _OptionTile(
                      option: option,
                      index: i,
                      selected: _selectedAnswer == i,
                      answered: _answered,
                      isCorrect: question.correctIndex == i,
                      onTap: () => _selectAnswer(i),
                      isDark: isDark,
                    );
                  }),

                  // Explanation after answering
                  if (_answered && question.explanation.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.lg),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: accentColor.withValues(alpha: 0.2),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            color: accentColor,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              question.explanation,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    height: 1.5,
                                    color: isDark
                                        ? Colors.white70
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
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

          // Next / Finish button
          if (_answered) ...[
            const SizedBox(height: AppSpacing.md),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _nextQuestion(provider),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  _currentQuestion < quiz.questions.length - 1
                      ? 'books.nextQuestion'.tr()
                      : 'books.seeResults'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildResultScreen(
    BuildContext context,
    BookProvider provider,
    bool isDark,
  ) {
    final quiz = provider.currentQuiz;
    final total = quiz?.questions.length ?? 0;
    final score = provider.quizScore;
    final pct = total > 0 ? score / total : 0.0;

    final resultIcon = pct >= 0.8
        ? Icons.celebration_rounded
        : pct >= 0.6
        ? Icons.thumb_up_rounded
        : Icons.menu_book_rounded;
    final resultIconColor = pct >= 0.8
        ? AppColors.warning
        : pct >= 0.6
        ? context.status.success
        : AppColorRoles.primary(isDark);
    final msg = pct >= 0.8
        ? 'books.quizExcellent'.tr()
        : pct >= 0.6
        ? 'books.quizGood'.tr()
        : 'books.quizKeepReading'.tr();

    final xpEarned = quiz != null && score > 0
        ? (quiz.xpReward * pct).round().clamp(5, quiz.xpReward)
        : 0;
    final accentColor = AppColorRoles.primary(isDark);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(resultIcon, size: 56, color: resultIconColor),
            const SizedBox(height: AppSpacing.lg),
            Text(
              msg,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.onGradient
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'books.quizScore'.tr(
                namedArgs: {'score': '$score', 'total': '$total'},
              ),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: isDark
                    ? Colors.white60
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            if (xpEarned > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.bolt_rounded, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      'games.xpEarned'.tr(namedArgs: {'xp': '$xpEarned'}),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(context),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                child: Text(
                  'books.backToBook'.tr(),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String option;
  final int index;
  final bool selected;
  final bool answered;
  final bool isCorrect;
  final VoidCallback onTap;
  final bool isDark;

  const _OptionTile({
    required this.option,
    required this.index,
    required this.selected,
    required this.answered,
    required this.isCorrect,
    required this.onTap,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final accentColor = AppColorRoles.primary(isDark);
    final bool showGreen = answered && isCorrect;
    final bool showRed = answered && selected && !isCorrect;

    Color borderColor;
    Color bgColor;
    Color textColor;

    if (showGreen) {
      borderColor = context.status.success;
      bgColor = context.status.success.withValues(alpha: 0.12);
      textColor = context.status.success;
    } else if (showRed) {
      borderColor = Theme.of(context).colorScheme.error;
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = Theme.of(context).colorScheme.error;
    } else if (selected) {
      borderColor = accentColor;
      bgColor = accentColor.withValues(alpha: 0.08);
      textColor = isDark
          ? AppColors.onGradient
          : Theme.of(context).colorScheme.onSurface;
    } else {
      borderColor = isDark ? Colors.white24 : AppColors.grey300;
      bgColor = isDark ? AppColors.surfaceDarkElevated : AppColors.onGradient;
      textColor = isDark
          ? AppColors.onGradient
          : Theme.of(context).colorScheme.onSurface;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 13,
        ),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Row(
          children: [
            // Option label (A, B, C, D)
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: showGreen
                    ? context.status.success
                    : showRed
                    ? Theme.of(context).colorScheme.error
                    : selected
                    ? accentColor
                    : (isDark ? Colors.white12 : AppColors.grey200),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + index), // A, B, C, D
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: (showGreen || showRed || selected)
                        ? AppColors.onGradient
                        : (isDark
                              ? Colors.white60
                              : Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                option,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.4,
                  fontWeight: (showGreen || showRed)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            if (showGreen)
              Icon(
                Icons.check_circle_rounded,
                color: context.status.success,
                size: 20,
              ),
            if (showRed)
              Icon(
                Icons.cancel_rounded,
                color: Theme.of(context).colorScheme.error,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
