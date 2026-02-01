import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lottie/lottie.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import '../../domain/entities/lesson_entity.dart';
import '../providers/learning_provider.dart';
import '../widgets/quiz_widget.dart';
import '../widgets/lesson_content_widget.dart';
import '../../../voice/presentation/widgets/tts_speed_selector.dart';
import '../../../progress/presentation/providers/streak_provider.dart';

/// Learning Session Screen
/// Handles the lesson learning flow with interactive exercises
class LearningSessionScreen extends StatefulWidget {
  final String lessonId;
  final String courseId;

  const LearningSessionScreen({
    Key? key,
    required this.lessonId,
    required this.courseId,
  }) : super(key: key);

  @override
  State<LearningSessionScreen> createState() => _LearningSessionScreenState();
}

class _LearningSessionScreenState extends State<LearningSessionScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LearningProvider>().startLesson(
            widget.courseId,
            widget.lessonId,
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        final shouldExit = await _showExitDialog(context);
        return shouldExit ?? false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Learning'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () async {
              final shouldExit = await _showExitDialog(context);
              if (shouldExit == true && mounted) {
                Navigator.pop(context);
              }
            },
          ),
          actions: [
            // TTS Speed Control Button
            const TtsSpeedButton(),
            Consumer<LearningProvider>(
              builder: (context, provider, child) {
                if (provider.currentLesson == null) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: Center(
                    child: Text(
                      '${provider.currentExerciseIndex + 1}/${provider.totalExercises}',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        body: Consumer<LearningProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) {
              return const LoadingScreen(message: 'Loading lesson...');
            }

            if (provider.error != null) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, size: 64, color: Colors.red),
                    const SizedBox(height: 16),
                    Text(provider.error!, textAlign: TextAlign.center),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        provider.startLesson(widget.courseId, widget.lessonId);
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (provider.currentLesson == null) {
              return const Center(child: Text('No lesson data'));
            }

            // Show completion screen
            if (provider.isCompleted) {
              return _buildCompletionScreen(context, provider);
            }

            // Show current exercise
            return Column(
              children: [
                // Progress bar
                LinearProgressIndicator(
                  value: provider.progress,
                  backgroundColor: Colors.grey[200],
                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                ),
                
                // Content
                Expanded(
                  child: _buildExerciseContent(context, provider),
                ),
                
                // Action buttons
                _buildActionButtons(context, provider),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildExerciseContent(BuildContext context, LearningProvider provider) {
    final exercise = provider.currentExercise;
    
    if (exercise == null) {
      return const Center(child: Text('No exercise available'));
    }

    switch (exercise.type) {
      case ExerciseType.multipleChoice:
      case ExerciseType.trueFalse:
        return QuizWidget(
          exercise: exercise,
          onAnswer: (answer) => provider.submitAnswer(answer),
          isAnswered: provider.isCurrentAnswered,
          userAnswer: provider.currentUserAnswer,
          isCorrect: provider.isCurrentCorrect,
        );
      
      case ExerciseType.fillInBlank:
      case ExerciseType.translate:
        return LessonContentWidget(
          exercise: exercise,
          onSubmit: (answer) => provider.submitAnswer(answer),
          isAnswered: provider.isCurrentAnswered,
          isCorrect: provider.isCurrentCorrect,
        );
      
      default:
        return Center(
          child: Text('Exercise type "${exercise.type}" not implemented yet'),
        );
    }
  }

  Widget _buildActionButtons(BuildContext context, LearningProvider provider) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Row(
        children: [
          // Skip button (only if not answered)
          if (!provider.isCurrentAnswered)
            TextButton(
              onPressed: () => provider.skipExercise(),
              child: const Text('Skip'),
            ),
          
          const Spacer(),
          
          // Check/Continue button
          ElevatedButton(
            onPressed: provider.isCurrentAnswered
                ? () => provider.nextExercise()
                : null, // Disabled until answered
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 48, vertical: 16),
              backgroundColor: provider.isCurrentAnswered
                  ? ((provider.isCurrentCorrect ?? false) ? Colors.green : Colors.orange)
                  : Colors.grey,
            ),
            child: Text(
              provider.isCurrentAnswered ? 'Continue' : 'Check',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompletionScreen(BuildContext context, LearningProvider provider) {
    final score = provider.score;
    final total = provider.totalExercises;
    final percentage = (score / total * 100).toInt();
    
    // Update streak when lesson is completed
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StreakProvider>().updateStreak();
    });
    
    return Stack(
      children: [
        // Confetti animation
        Positioned.fill(
          child: IgnorePointer(
            child: Lottie.asset(
              'animation/Confetti.json',
              fit: BoxFit.cover,
              repeat: false,
            ),
          ),
        ),
        
        // Content
        Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Trophy icon with glow effect
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 800),
                curve: Curves.elasticOut,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: child,
                  );
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Container(
                      width: 140,
                      height: 140,
                      decoration: BoxDecoration(
                        color: (percentage >= 80 ? Colors.amber : Colors.green).withOpacity(0.2),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: (percentage >= 80 ? Colors.amber : Colors.green).withOpacity(0.3),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ],
                      ),
                    ),
                    if (percentage >= 80)
                      const LottieAnimationWidget(
                        animation: LottieAnimation.starBurst,
                        width: 120,
                        height: 120,
                        repeat: false,
                      )
                    else
                      AnimatedCheckmark(
                        color: Colors.green,
                        size: 80,
                      ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // Animated Title
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: const Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 20 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: Column(
                  children: [
                    Text(
                      percentage >= 80 ? '🎉 Excellent! 🎉' : '✨ Well Done! ✨',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'You scored $score/$total ($percentage%)',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            color: Colors.grey[600],
                          ),
                    ),
                  ],
                ),
              ),
              
              const SizedBox(height: 32),
              
              // XP earned with animation
              if (provider.xpEarned > 0)
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.0, end: 1.0),
                  duration: const Duration(milliseconds: 800),
                  curve: Curves.bounceOut,
                  builder: (context, value, child) {
                    return Transform.scale(
                      scale: value,
                      child: child,
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.amber.shade400, Colors.orange.shade400],
                      ),
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withOpacity(0.4),
                          blurRadius: 15,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.stars, color: Colors.white, size: 28),
                        const SizedBox(width: 8),
                        Text(
                          '+${provider.xpEarned} XP',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              
              const SizedBox(height: 48),
              
              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              
              const SizedBox(height: 12),
              
              if (percentage < 80)
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: () {
                      provider.restartLesson();
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: const Text(
                      'Practice Again',
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<bool?> _showExitDialog(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Exit Lesson?'),
        content: const Text(
          'Your progress will be saved, but you won\'t earn XP until you complete the lesson.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Exit'),
          ),
        ],
      ),
    );
  }
}
