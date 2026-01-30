import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/flashcard_widget.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/review_quality_buttons.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/session_header.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/session_complete_screen.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/tts_speed_selector.dart';

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
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _slideAnimation = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0),
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeInOut,
    ));

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
    final provider = context.read<FlashcardProvider>();

    // Animate card sliding out
    await _slideController.forward();

    // Submit review
    await provider.submitReview(quality);

    // Check if session is complete
    if (provider.currentSession?.isCompleted ?? false) {
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SessionCompleteScreen(
              session: provider.currentSession!,
            ),
          ),
        );
      }
      return;
    }

    // Reset animation for next card
    _slideController.reset();
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
        title: const Text(
          'Review Session',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: true,
        actions: const [
          // TTS Speed Control Button
          TtsSpeedButton(),
          SizedBox(width: 8),
        ],
      ),
      body: Consumer<FlashcardProvider>(
        builder: (context, provider, child) {
          // Loading state
          if (provider.isLoading && !provider.hasSession) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading vocabulary...'),
                ],
              ),
            );
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
                      color: Colors.orange,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      provider.errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        provider.clearError();
                        provider.startReviewSession();
                      },
                      child: const Text('Try Again'),
                    ),
                  ],
                ),
              ),
            );
          }

          // No session
          if (!provider.hasSession) {
            return const Center(
              child: Text('No review session available'),
            );
          }

          final session = provider.currentSession!;
          final currentCard = session.currentCard;

          if (currentCard == null) {
            return const Center(
              child: Text('Session complete!'),
            );
          }

          return Column(
            children: [
              // Session Header (Progress, Stats)
              SessionHeader(session: session),

              // Flashcard
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: SlideTransition(
                      position: _slideAnimation,
                      child: FlashcardWidget(
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

              // Review Quality Buttons (Show after flip)
              if (provider.isCardFlipped)
                ReviewQualityButtons(
                  onQualitySelected: _handleReview,
                  isLoading: provider.isLoading,
                ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  void _showExitDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Review?'),
        content: const Text(
          'Your progress will be saved, but you can continue this session later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final provider = context.read<FlashcardProvider>();
              provider.endSession();
              Navigator.of(context).pop(); // Close dialog
              Navigator.of(context).pop(); // Close screen
            },
            child: const Text(
              'Exit',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }
}
