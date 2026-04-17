import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_theme.dart';
import '../providers/book_provider.dart';

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
          'Chapter ${widget.chapter} Quiz',
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: Consumer<BookProvider>(
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
                'Quiz not available.',
                style: TextStyle(
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                ),
              ),
            );
          }

          final question = quiz.questions[_currentQuestion];
          return _buildQuestionView(context, provider, question, quiz, isDark);
        },
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
                    valueColor: const AlwaysStoppedAnimation<Color>(
                      AppColors.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${_currentQuestion + 1}/$total',
                style: TextStyle(
                  fontSize: 13,
                  color: isDark ? Colors.white54 : AppColors.textGrey,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 28),

          // Question
          Text(
            question.question,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              height: 1.45,
              color: isDark ? Colors.white : AppColors.textDark,
            ),
          ),
          const SizedBox(height: 24),

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
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.info_outline_rounded,
                    color: AppColors.primary,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      question.explanation,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: isDark ? Colors.white70 : AppColors.textGrey,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const Spacer(),

          // Next / Finish button
          if (_answered)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _nextQuestion(provider),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentQuestion < quiz.questions.length - 1
                      ? 'Next Question'
                      : 'See Results',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
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
        ? AppColors.greenSuccessBright
        : Colors.blue;
    final msg = pct >= 0.8
        ? 'Excellent!'
        : pct >= 0.6
        ? 'Good job!'
        : 'Keep reading!';

    final xpEarned = quiz != null && score > 0
        ? (quiz.xpReward * pct).round().clamp(5, quiz.xpReward)
        : 0;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(resultIcon, size: 56, color: resultIconColor),
            const SizedBox(height: 16),
            Text(
              msg,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: isDark ? Colors.white : AppColors.textDark,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$score / $total correct',
              style: TextStyle(
                fontSize: 16,
                color: isDark ? Colors.white60 : AppColors.textGrey,
              ),
            ),
            const SizedBox(height: 24),
            if (xpEarned > 0)
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.bolt_rounded, color: AppColors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '+$xpEarned XP earned!',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'Back to Book',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
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
    final bool showGreen = answered && isCorrect;
    final bool showRed = answered && selected && !isCorrect;

    Color borderColor;
    Color bgColor;
    Color textColor;

    if (showGreen) {
      borderColor = AppColors.greenSuccessBright;
      bgColor = AppColors.greenSuccessBright.withValues(alpha: 0.12);
      textColor = AppColors.greenSuccessBright;
    } else if (showRed) {
      borderColor = AppColors.errorBright;
      bgColor = Colors.red.withValues(alpha: 0.1);
      textColor = AppColors.errorBright;
    } else if (selected) {
      borderColor = AppColors.primary;
      bgColor = AppColors.primary.withValues(alpha: 0.08);
      textColor = isDark ? Colors.white : AppColors.textDark;
    } else {
      borderColor = isDark ? Colors.white24 : AppColors.grey300;
      bgColor = isDark ? AppColors.surfaceDarkElevated : Colors.white;
      textColor = isDark ? Colors.white : AppColors.textDark;
    }

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(12),
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
                    ? AppColors.greenSuccessBright
                    : showRed
                    ? AppColors.errorBright
                    : selected
                    ? AppColors.primary
                    : (isDark ? Colors.white12 : AppColors.grey200),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Text(
                  String.fromCharCode(65 + index), // A, B, C, D
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: (showGreen || showRed || selected)
                        ? Colors.white
                        : (isDark ? Colors.white60 : AppColors.textGrey),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                option,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.4,
                  fontWeight: (showGreen || showRed)
                      ? FontWeight.w600
                      : FontWeight.normal,
                  color: textColor,
                ),
              ),
            ),
            if (showGreen)
              const Icon(
                Icons.check_circle_rounded,
                color: AppColors.greenSuccessBright,
                size: 20,
              ),
            if (showRed)
              const Icon(
                Icons.cancel_rounded,
                color: AppColors.errorBright,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
