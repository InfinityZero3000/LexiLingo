import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/game_icon.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/quiz_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/flashcard_review_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/quiz_review_screen.dart';
import 'package:lexilingo_app/features/vocabulary/vocabulary_di.dart'
    as vocab_di;

/// Daily Review Card Widget
/// Shows due vocabulary count and starts review session
/// Clean Code: Single responsibility - display review status
class DailyReviewCard extends StatefulWidget {
  const DailyReviewCard({super.key});

  @override
  State<DailyReviewCard> createState() => _DailyReviewCardState();
}

class _DailyReviewCardState extends State<DailyReviewCard> {
  int _dueCount = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadDueCount();
  }

  Future<void> _loadDueCount() async {
    final result = await vocab_di
        .getIt<VocabularyRepository>()
        .getVocabularyStats();
    if (mounted) {
      setState(() {
        _dueCount = result.fold(
          (failure) => 0,
          (stats) => stats['due_for_review'] as int? ?? 0,
        );
        _isLoading = false;
      });
    }
  }

  void _startFlashcards() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => vocab_di.getIt<FlashcardProvider>(),
          child: const FlashcardReviewScreen(),
        ),
      ),
    );
  }

  void _startQuiz() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => vocab_di.getIt<QuizProvider>(),
          child: const QuizReviewScreen(),
        ),
      ),
    );
  }

  void _startReview() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'vocabQuiz.chooseMode'.tr(),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _ReviewModeTile(
                icon: Icons.quiz_rounded,
                title: 'vocabQuiz.modeQuizTitle'.tr(),
                subtitle: 'vocabQuiz.modeQuizSubtitle'.tr(),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startQuiz();
                },
              ),
              const SizedBox(height: 12),
              _ReviewModeTile(
                icon: Icons.style_rounded,
                title: 'vocabQuiz.modeFlashcardTitle'.tr(),
                subtitle: 'vocabQuiz.modeFlashcardSubtitle'.tr(),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _startFlashcards();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleCardTap() {
    if (_isLoading) return;
    if (_dueCount > 0) {
      _startReview();
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('home.allCaughtUpMessage'.tr()),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _handleCardTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                isDark ? accent : AppColors.primary,
                isDark
                    ? AppColorRoles.primaryDeep(true)
                    : const Color(0xFF0D6ABD),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (isDark ? accent : AppColors.primary).withValues(
                  alpha: 0.25,
                ),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const AppGameIcon(GameIcon.flashcards, size: 32),
              ),

              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.dailyReview'.tr(),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.surface,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    _isLoading
                        ? const SizedBox(
                            width: 80,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            _dueCount > 0
                                ? 'home.wordsWaiting'.tr(
                                    namedArgs: {'count': '$_dueCount'},
                                  )
                                : 'home.allCaughtUpTapToCheck'.tr(),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              fontSize: 12,
                            ),
                          ),
                  ],
                ),
              ),

              // Button
              if (!_isLoading && _dueCount > 0)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    onTap: _handleCardTap,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      child: Text(
                        'home.startReview'.tr(),
                        style: const TextStyle(
                          color: AppColors.slate900,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReviewModeTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ReviewModeTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    return Material(
      color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
