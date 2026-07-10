import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/flashcard_review_screen.dart';
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

  void _startReview() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider(
          create: (_) => vocab_di.getIt<FlashcardProvider>(),
          child: const FlashcardReviewScreen(),
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
                child: Icon(
                  Icons.style,
                  color: Theme.of(context).colorScheme.surface,
                  size: 24,
                ),
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
                    onTap: _startReview,
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
