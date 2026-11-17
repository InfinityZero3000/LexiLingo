import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/flashcard_widget.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/review_deck.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/review_quality_buttons.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/session_header.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/session_complete_screen.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/vocabulary_speaking_practice_screen.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/tts_speed_selector.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Flashcard Review Screen (Presentation Layer)
/// Interactive flashcard review with animations
/// Clean Code: Single responsibility - handles review UI only
class FlashcardReviewScreen extends StatefulWidget {
  const FlashcardReviewScreen({super.key});

  @override
  State<FlashcardReviewScreen> createState() => _FlashcardReviewScreenState();
}

class _FlashcardReviewScreenState extends State<FlashcardReviewScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 320),
      vsync: this,
    );

    // Start review session
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<FlashcardProvider>();
      if (!provider.hasSession) {
        provider.startReviewSession();
      }
    });
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  Future<void> _handleReview(ReviewQuality quality) async {
    // The buttons only lock once the provider is loading, which is after the
    // card has flown out; a second tap in that window rated the card twice.
    if (_submitting) return;
    _submitting = true;
    final provider = context.read<FlashcardProvider>();

    try {
      await _slideController.forward();
      await provider.submitReview(quality);

      if (provider.currentSession?.isCompleted ?? false) {
        if (mounted) {
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) =>
                  SessionCompleteScreen(session: provider.currentSession!),
            ),
          );
        }
        return;
      }
      if (mounted) _slideController.reset();
    } finally {
      _submitting = false;
    }
  }

  void _openSpeakingPractice() {
    final provider = context.read<FlashcardProvider>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: provider,
          child: const VocabularySpeakingPracticeScreen(),
        ),
      ),
    );
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
          onPressed: () {
            _showExitDialog(context);
          },
        ),
        title: Text(
          'flashcard.reviewSessionTitle'.tr(),
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'lesson.exercise.speakingTitle'.tr(),
            icon: const Icon(Icons.mic_none_rounded),
            onPressed: _openSpeakingPractice,
          ),
          // TTS Speed Control Button
          const TtsSpeedButton(),
          const SizedBox(width: 8),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: Consumer<FlashcardProvider>(
          builder: (context, provider, child) {
            // Loading state
            if (provider.isLoading && !provider.hasSession) {
              return LoadingScreen(message: 'flashcard.loadingVocabulary'.tr());
            }

            // Error state
            if (provider.errorMessage != null) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: AppColors.orange,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        provider.errorMessage!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge!,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          provider.clearError();
                          provider.startReviewSession();
                        },
                        child: Text('flashcard.tryAgain'.tr()),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (provider.nothingDue) {
              final theme = Theme.of(context);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline_rounded,
                        size: 64,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'flashcard.nothingDueTitle'.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'flashcard.nothingDueBody'.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: () => Navigator.of(context).maybePop(),
                        child: Text('flashcard.nothingDueAction'.tr()),
                      ),
                    ],
                  ),
                ),
              );
            }

            // No session
            if (!provider.hasSession) {
              return Center(
                child: Text('flashcard.noReviewSessionAvailable'.tr()),
              );
            }

            final session = provider.currentSession!;
            final currentCard = session.currentCard;

            if (currentCard == null) {
              if (!session.isCompleted) {
                // Loaded cards exhausted while background preload is still running
                return const Center(
                  child: CircularProgressIndicator(strokeWidth: 3),
                );
              }
              return Center(child: Text('flashcard.sessionComplete'.tr()));
            }

            return SafeArea(
              child: Column(
                children: [
                  // Session Header (Progress, Stats)
                  SessionHeader(session: session),

                  // Flashcard on its pile — fixed position, never shifts
                  // when the buttons appear.
                  Expanded(
                    child: Align(
                      alignment: const Alignment(0, -0.15),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: ReviewDeck(
                          behind: session.remainingCards - 1,
                          exit: _slideController,
                          child: FlashcardWidget(
                            // A new word gets a new widget, face up. Reusing
                            // the old one flipped it back over 600ms and
                            // showed the new word's answer on the way.
                            key: ValueKey(currentCard.userVocabulary.id),
                            card: currentCard,
                            isFlipped: provider.isCardFlipped,
                            onTap: () {
                              provider.flipCard();
                            },
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Review Quality Buttons — always occupies space to keep card fixed
                  Visibility(
                    visible: provider.isCardFlipped,
                    maintainSize: true,
                    maintainAnimation: true,
                    maintainState: true,
                    child: AnimatedSlide(
                      offset: provider.isCardFlipped
                          ? Offset.zero
                          : const Offset(0, 0.3),
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: provider.isCardFlipped ? 1.0 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: ReviewQualityButtons(
                          onQualitySelected: _handleReview,
                          isLoading: provider.isLoading,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('flashcard.exitReviewTitle'.tr()),
        content: Text('flashcard.exitReviewMessage'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text('common.cancel'.tr()),
          ),
          TextButton(
            onPressed: () {
              final provider = context.read<FlashcardProvider>();
              provider.endSession();
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close screen
            },
            child: Text(
              'lesson.exit'.tr(),
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
      ),
    );
  }
}
