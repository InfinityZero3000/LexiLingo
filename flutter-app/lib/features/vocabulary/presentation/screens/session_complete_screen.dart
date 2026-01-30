import 'package:flutter/material.dart';
import 'package:confetti/confetti.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/review_session_entity.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';

/// Session Complete Screen (Presentation Layer)
/// Shows review session results with celebration animation
/// Clean Code: Single responsibility - display session results
class SessionCompleteScreen extends StatefulWidget {
  final ReviewSessionEntity session;

  const SessionCompleteScreen({
    super.key,
    required this.session,
  });

  @override
  State<SessionCompleteScreen> createState() => _SessionCompleteScreenState();
}

class _SessionCompleteScreenState extends State<SessionCompleteScreen> {
  late ConfettiController _confettiController;

  @override
  void initState() {
    super.initState();
    _confettiController = ConfettiController(duration: const Duration(seconds: 3));
    
    // Start confetti animation
    Future.delayed(const Duration(milliseconds: 500), () {
      _confettiController.play();
    });
    
    // Update streak after review session complete
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreakProvider>().updateStreak();
    });
  }

  @override
  void dispose() {
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final accuracy = session.accuracy;
    final duration = session.completedAt!.difference(session.startedAt);

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Stack(
        children: [
          // Confetti animation
          Align(
            alignment: Alignment.topCenter,
            child: ConfettiWidget(
              confettiController: _confettiController,
              blastDirectionality: BlastDirectionality.explosive,
              emissionFrequency: 0.05,
              numberOfParticles: 20,
              gravity: 0.3,
              colors: const [
                AppColors.primary,
                AppColors.accentYellow,
                AppColors.greenSuccess,
                Colors.red,
                Colors.purple,
              ],
            ),
          ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  const SizedBox(height: 40),

                  // Success icon
                  Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: AppColors.greenSuccess.withOpacity(0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_circle,
                      size: 80,
                      color: AppColors.greenSuccess,
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Title
                  const Text(
                    'Session Complete!',
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 16),

                  // Motivational message
                  Text(
                    _getMotivationalMessage(accuracy),
                    style: TextStyle(
                      fontSize: 18,
                      color: AppColors.textGrey,
                    ),
                    textAlign: TextAlign.center,
                  ),

                  const SizedBox(height: 48),

                  // Stats cards
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        children: [
                          _StatCard(
                            icon: Icons.assignment_turned_in,
                            label: 'Words Reviewed',
                            value: '${session.totalCards}',
                            color: AppColors.primary,
                          ),
                          const SizedBox(height: 16),
                          _StatCard(
                            icon: Icons.check_circle,
                            label: 'Correct Answers',
                            value: '${session.correctCount}',
                            subtitle: '${accuracy.toStringAsFixed(1)}% accuracy',
                            color: AppColors.greenSuccess,
                          ),
                          const SizedBox(height: 16),
                          _StatCard(
                            icon: Icons.star,
                            label: 'XP Earned',
                            value: '+${session.totalXpEarned}',
                            color: AppColors.accentYellow,
                          ),
                          const SizedBox(height: 16),
                          _StatCard(
                            icon: Icons.timer,
                            label: 'Time Spent',
                            value: _formatDuration(duration),
                            color: AppColors.textGrey,
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                          },
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Back to Library'),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            // Navigate to review again
                          },
                          style: ElevatedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                          child: const Text('Review More'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getMotivationalMessage(double accuracy) {
    if (accuracy >= 90) {
      return 'Excellent work! You\'re mastering these words! 🎉';
    } else if (accuracy >= 70) {
      return 'Great job! Keep up the good work! 👏';
    } else if (accuracy >= 50) {
      return 'Good effort! Practice makes perfect! 💪';
    } else {
      return 'Keep practicing! You\'re making progress! 🌟';
    }
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds % 60;
    return '${minutes}m ${seconds}s';
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    this.subtitle,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).brightness == Brightness.dark
            ? const Color(0xFF1C2632)
            : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: color.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: color,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textGrey,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textGrey.withOpacity(0.7),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
