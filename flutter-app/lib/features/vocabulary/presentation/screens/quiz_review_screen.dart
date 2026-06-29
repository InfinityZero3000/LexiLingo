import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/quiz_question_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/quiz_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/session_complete_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/quiz_option_card.dart';

/// Quizlet-style multiple-choice review over FSRS-due words.
/// Tests each word in both directions (term ↔ meaning); results feed FSRS.
class QuizReviewScreen extends StatefulWidget {
  /// How the session is started. Defaults to FSRS-due words; deck/topic
  /// callers pass their own loader.
  final Future<void> Function(QuizProvider)? sessionStarter;

  const QuizReviewScreen({super.key, this.sessionStarter});

  @override
  State<QuizReviewScreen> createState() => _QuizReviewScreenState();
}

class _QuizReviewScreenState extends State<QuizReviewScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<QuizProvider>();
      if (!provider.hasSession && !provider.isLoading) {
        (widget.sessionStarter ?? (p) => p.startQuizSession())(provider);
      }
    });
  }

  Future<void> _handleAdvance(QuizProvider provider) async {
    final wasLast = provider.currentQuestionNumber >= provider.totalQuestions;
    provider.next();
    if (wasLast) {
      await provider.finishPending();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) =>
              SessionCompleteScreen(session: provider.buildSummary()),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _showExitDialog(context),
        ),
        title: Consumer<QuizProvider>(
          builder: (context, provider, _) {
            if (!provider.hasSession) return const SizedBox.shrink();
            return Text(
              '${provider.currentQuestionNumber} / ${provider.totalQuestions}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            );
          },
        ),
        centerTitle: true,
      ),
      body: Consumer<QuizProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && !provider.hasSession) {
            return LoadingScreen(message: 'vocabQuiz.loading'.tr());
          }

          if (provider.errorMessage != null) {
            return _ErrorState(
              message: provider.errorMessage!,
              onRetry: () {
                provider.clearError();
                (widget.sessionStarter ?? (p) => p.startQuizSession())(
                  provider,
                );
              },
            );
          }

          final question = provider.currentQuestion;
          if (question == null) {
            return Center(child: Text('vocabQuiz.empty'.tr()));
          }

          return _QuizBody(
            provider: provider,
            question: question,
            onAdvance: () => _handleAdvance(provider),
          );
        },
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('vocabQuiz.exitTitle'.tr()),
        content: Text('vocabQuiz.exitMessage'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              Navigator.of(context).pop();
            },
            child: Text(
              'lesson.exit'.tr(),
              style: const TextStyle(color: AppColors.errorBright),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuizBody extends StatelessWidget {
  final QuizProvider provider;
  final QuizQuestionEntity question;
  final VoidCallback onAdvance;

  const _QuizBody({
    required this.provider,
    required this.question,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final answered = provider.isAnswered;
    final isTerm = question.direction == QuizDirection.termToMeaning;
    final promptLabel =
        isTerm ? 'vocabQuiz.term'.tr() : 'vocabQuiz.definition'.tr();

    return Column(
      children: [
        // Progress bar
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: provider.progress,
              minHeight: 8,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              valueColor:
                  const AlwaysStoppedAnimation(AppColors.greenSuccessBright),
            ),
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              // Prompt card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark
                      ? AppColors.surfaceDarkMuted
                      : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      promptLabel,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question.prompt,
                      style: TextStyle(
                        fontSize: isTerm ? 28 : 20,
                        height: 1.4,
                        fontWeight:
                            isTerm ? FontWeight.bold : FontWeight.w500,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              Text(
                'vocabQuiz.chooseCorrect'.tr(),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),

              ...List.generate(question.options.length, (i) {
                final option = question.options[i];
                return QuizOptionCard(
                  index: i + 1,
                  text: option.text,
                  answered: answered,
                  isCorrect: option.isCorrect,
                  isSelected: provider.selectedIndex == i,
                  onTap: answered ? null : () => provider.answer(i),
                );
              }),
            ],
          ),
        ),

        // Feedback + continue
        if (answered) _FeedbackBar(provider: provider, onAdvance: onAdvance),
      ],
    );
  }
}

class _FeedbackBar extends StatelessWidget {
  final QuizProvider provider;
  final VoidCallback onAdvance;

  const _FeedbackBar({required this.provider, required this.onAdvance});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selected = provider.selectedIndex;
    final isCorrect = selected != null &&
        provider.currentQuestion!.options[selected].isCorrect;
    final color =
        isCorrect ? AppColors.greenSuccessBright : AppColors.errorBright;
    final isLast =
        provider.currentQuestionNumber >= provider.totalQuestions;

    return Container(
      padding: EdgeInsets.fromLTRB(
        20,
        16,
        20,
        16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppColors.surfaceDarkMuted
            : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                isCorrect
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: color,
              ),
              const SizedBox(width: 8),
              Text(
                isCorrect
                    ? 'vocabQuiz.correct'.tr()
                    : 'vocabQuiz.incorrect'.tr(),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onAdvance,
              style: ElevatedButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                isLast
                    ? 'vocabQuiz.finish'.tr()
                    : 'vocabQuiz.continueLabel'.tr(),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: AppColors.orange),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: onRetry,
              child: Text('vocabQuiz.tryAgain'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
