import 'dart:math';
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

    final messages = [
      'All caught up for today. Come back tomorrow!',
      'You are doing great! See you tomorrow!',
      'Your daily goal is clear. Rest well!',
      'No more words to learn today. Great job!',
      'You dominated today\'s review!',
      'Rest your brain. You\'ve earned it!',
      'Consistency is key! You are done for today.',
      'Awesome work! Let\'s learn more tomorrow!',
      'Empty queue! You are a vocabulary master!',
      'Mission accomplished! Enjoy your free time.',
      'You crushed it today! See you on the next one.',
      'Nothing left to review. You\'re on a roll!',
      'Brain workout complete. Take a breather!',
      'All words conquered! Time to relax.',
      'Stellar effort today! Catch you tomorrow.',
      'Zero pending reviews. You are unstoppable!',
      'Daily target smashed! Keep up the momentum.',
      'You\'ve cleared the board! Fantastic job.',
      'Vocabulary expanded! Rest up for tomorrow.',
      'Another day, another victory. Keep it up!',
      'Review queue is empty. Go treat yourself!',
      'You nailed your daily practice! Have a great day.',
      'Your memory is serving you well. Good job!',
      'Done and dusted! See you back here tomorrow.',
      'Perfection! You\'ve learned everything for today.',
      'That\'s a wrap! Your brain deserves a break.',
      'You cleared your learning queue! Stay awesome.',
      'High five! All daily words absorbed.',
      'Great session! Let the newly learned words sink in.',
      'You\'re officially off the clock. See you tomorrow!',
    ];

    final randomMsg = messages[Random().nextInt(messages.length)];

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(randomMsg), duration: const Duration(seconds: 2)),
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
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                isDark ? accent : AppColors.primary,
                isDark ? AppColorRoles.primaryDeep(true) : const Color(0xFF0D6ABD),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: (isDark ? accent : AppColors.primary).withValues(
                  alpha: 0.3,
                ),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(
                  Icons.style,
                  color: Theme.of(context).colorScheme.surface,
                  size: 32,
                ),
              ),

              const SizedBox(width: 16),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Daily Review',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.surface,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _isLoading
                        ? const SizedBox(
                            width: 100,
                            child: LinearProgressIndicator(
                              backgroundColor: Colors.white24,
                              valueColor: AlwaysStoppedAnimation(Colors.white),
                            ),
                          )
                        : Text(
                            _dueCount > 0
                                ? '$_dueCount words waiting'
                                : 'All caught up! Tap to check again',
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.surface.withValues(alpha: 0.9),
                              fontSize: 14,
                            ),
                          ),
                  ],
                ),
              ),

              // Button
              if (!_isLoading && _dueCount > 0)
                Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  child: InkWell(
                    onTap: _startReview,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 12,
                      ),
                      child: const Text(
                        'Start',
                        style: TextStyle(
                          color: AppColors.slate900,
                          fontSize: 16,
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
