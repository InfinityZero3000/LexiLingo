import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../games/data/repositories/games_repository.dart';
import '../../domain/entities/news_entities.dart';
import '../providers/news_provider.dart';

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
      context.read<NewsProvider>().loadQuiz(widget.article.id);
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
        title: const Text('Comprehension Quiz'),
        leading: IconButton(
          onPressed: () {
            context.read<NewsProvider>().resetQuiz();
            Navigator.pop(context);
          },
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: FadeTransition(
        opacity: _fadeController,
        child: Consumer<NewsProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingQuiz) {
              return const Center(child: CircularProgressIndicator());
            }

            if (provider.currentQuiz == null) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.quiz_outlined,
                      size: 64,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Quiz not available',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                      ),
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
                style: TextStyle(
                  color: cefrColor,
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                ),
              ),
              const SizedBox(width: 12),
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
        const SizedBox(height: 16),

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
            child: FilledButton.icon(
              onPressed: provider.answers.length == quiz.totalQuestions
                  ? () {
                      provider.submitQuiz();
                      // Award XP via the shared XP endpoint (skill: progress-xp-system)
                      sl<GamesRepository>()
                          .awardXP(
                            source: 'news',
                            baseXp: quiz.xpReward,
                            sourceId: widget.article.id,
                          )
                          .then((_) {})
                          .catchError((_) {});
                    }
                  : null,
              icon: const Icon(Icons.check_circle_rounded, size: 20),
              label: const Text('Submit Answers'),
              style: FilledButton.styleFrom(
                backgroundColor: cefrColor,
                disabledBackgroundColor: cefrColor.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
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
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _questionTypeColor(question.type).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              question.type.toUpperCase(),
              style: TextStyle(
                color: _questionTypeColor(question.type),
                fontWeight: FontWeight.w700,
                fontSize: 10,
                letterSpacing: 0.5,
              ),
            ),
          ),
          const SizedBox(height: 10),

          // Question text
          Text(
            question.question,
            style: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 15,
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
              padding: const EdgeInsets.only(bottom: 8),
              child: GestureDetector(
                onTap: () => provider.answerQuestion(question.id, index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? cefrColor.withValues(alpha: 0.08)
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.03)
                              : Colors.grey.shade50),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isSelected
                          ? cefrColor
                          : (isDark
                                ? Colors.white.withValues(alpha: 0.08)
                                : Colors.grey.shade200),
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
                                    ? Colors.white.withValues(alpha: 0.06)
                                    : Colors.grey.shade100),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            String.fromCharCode(65 + index), // A, B, C, D
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : (isDark
                                        ? Colors.white54
                                        : Colors.grey.shade600),
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
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
                  style: TextStyle(
                    fontSize: 14,
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
          const SizedBox(height: 8),
          Text(
            _resultSubMessage(percentage),
            style: TextStyle(
              color: isDark ? Colors.white54 : AppColors.textGrey,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),

          // XP reward
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            decoration: BoxDecoration(
              color: cefrColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: cefrColor.withValues(alpha: 0.2)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.star_rounded, color: cefrColor, size: 24),
                const SizedBox(width: 8),
                Text(
                  '+${quiz.xpReward} XP',
                  style: TextStyle(
                    color: cefrColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),

          // Question review
          ...quiz.questions.asMap().entries.map((entry) {
            final q = entry.value;
            final userAnswer = provider.answers[q.id];
            final isCorrect = userAnswer == q.correctIndex;

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.04)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isCorrect
                      ? Colors.green.withValues(alpha: 0.3)
                      : Colors.red.withValues(alpha: 0.3),
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
                        color: isCorrect ? Colors.green : Colors.red,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          q.question,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (!isCorrect) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Correct: ${q.options[q.correctIndex]}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (q.explanation.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      q.explanation,
                      style: TextStyle(
                        color: isDark ? Colors.white38 : AppColors.textGrey,
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ],
                ],
              ),
            );
          }),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    provider.resetQuiz();
                    provider.loadQuiz(widget.article.id);
                  },
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Retry'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: cefrColor,
                    side: BorderSide(color: cefrColor),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () {
                    provider.resetQuiz();
                    Navigator.pop(context);
                  },
                  icon: const Icon(Icons.done_all_rounded, size: 18),
                  label: const Text('Done'),
                  style: FilledButton.styleFrom(
                    backgroundColor: cefrColor,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
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
        return const Color(0xFF4CAF50);
      case 'A2':
        return const Color(0xFF8BC34A);
      case 'B1':
        return const Color(0xFFFFC107);
      case 'B2':
        return const Color(0xFFFF9800);
      case 'C1':
        return const Color(0xFFFF5722);
      case 'C2':
        return const Color(0xFF9C27B0);
      default:
        return AppColors.primary;
    }
  }

  Color _questionTypeColor(String type) {
    switch (type) {
      case 'comprehension':
        return const Color(0xFF137FEC);
      case 'vocabulary':
        return const Color(0xFF9C27B0);
      case 'grammar':
        return const Color(0xFFFF9800);
      default:
        return AppColors.primary;
    }
  }

  String _resultMessage(int percentage) {
    if (percentage >= 80) return 'Excellent!';
    if (percentage >= 60) return 'Good job!';
    if (percentage >= 40) return 'Keep practicing!';
    return 'Don\'t give up!';
  }

  String _resultSubMessage(int percentage) {
    if (percentage >= 80)
      return 'You have a great understanding of this article.';
    if (percentage >= 60)
      return 'You\'re on the right track. Review the highlighted words.';
    if (percentage >= 40)
      return 'Try re-reading the article and focusing on key details.';
    return 'Re-read the article carefully before trying again.';
  }
}
