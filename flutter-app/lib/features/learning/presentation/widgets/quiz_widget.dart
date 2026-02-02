import 'package:flutter/material.dart';
import '../../domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';

/// Quiz Widget for Multiple Choice and True/False exercises
class QuizWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const QuizWidget({
    Key? key,
    required this.exercise,
    required this.onAnswer,
    this.isAnswered = false,
    this.userAnswer,
    this.isCorrect,
  }) : super(key: key);

  @override
  State<QuizWidget> createState() => _QuizWidgetState();
}

class _QuizWidgetState extends State<QuizWidget> with SingleTickerProviderStateMixin {
  String? _selectedAnswer;
  late AnimationController _animationController;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _selectedAnswer = widget.userAnswer;
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    );
  }

  @override
  void didUpdateWidget(QuizWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnswered && !oldWidget.isAnswered) {
      _animationController.forward();
    }
    if (widget.exercise != oldWidget.exercise) {
      _selectedAnswer = null;
      _animationController.reset();
    }
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Question
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _getQuestionTypeLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          widget.exercise.question,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // TTS Speak Button for question
                      SpeakIconButton(
                        text: widget.exercise.question,
                        size: 24,
                        color: Theme.of(context).primaryColor,
                      ),
                    ],
                  ),
                  
                  // Show hint if available
                  if (widget.exercise.hint != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.lightbulb_outline, 
                              size: 20, color: Colors.blue),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              widget.exercise.hint!,
                              style: const TextStyle(
                                fontSize: 14,
                                color: Colors.blue,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Options
          ...widget.exercise.options!.map((option) {
            final isSelected = _selectedAnswer == option;
            final isCorrectAnswer = widget.exercise.correctAnswer == option;
            final showResult = widget.isAnswered;
            
            Color? backgroundColor;
            Color? borderColor;
            IconData? icon;
            
            if (showResult) {
              if (isCorrectAnswer) {
                backgroundColor = Colors.green.withValues(alpha: 0.1);
                borderColor = Colors.green;
                icon = Icons.check_circle;
              } else if (isSelected && !isCorrectAnswer) {
                backgroundColor = Colors.red.withValues(alpha: 0.1);
                borderColor = Colors.red;
                icon = Icons.cancel;
              }
            } else if (isSelected) {
              backgroundColor = Theme.of(context).primaryColor.withValues(alpha: 0.1);
              borderColor = Theme.of(context).primaryColor;
            }
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: InkWell(
                onTap: widget.isAnswered
                    ? null
                    : () {
                        setState(() => _selectedAnswer = option);
                        widget.onAnswer(option);
                      },
                borderRadius: BorderRadius.circular(12),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: backgroundColor ?? Colors.grey[50],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: borderColor ?? Colors.grey[300]!,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                          ),
                        ),
                      ),
                      if (showResult && icon != null)
                        Icon(
                          icon,
                          color: isCorrectAnswer ? Colors.green : Colors.red,
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
          
          // Explanation (shown after answering)
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 24),
            FadeTransition(
              opacity: _animation,
              child: Card(
                color: widget.isCorrect! 
                    ? Colors.green.withValues(alpha: 0.1)
                    : Colors.orange.withValues(alpha: 0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: widget.isCorrect! ? Colors.green : Colors.orange,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.isCorrect! 
                                ? Icons.check_circle 
                                : Icons.info_outline,
                            color: widget.isCorrect! ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            widget.isCorrect! ? 'Correct!' : 'Not quite',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: widget.isCorrect! ? Colors.green : Colors.orange,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        widget.exercise.explanation!,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getQuestionTypeLabel() {
    switch (widget.exercise.type) {
      case ExerciseType.multipleChoice:
        return 'MULTIPLE CHOICE';
      case ExerciseType.trueFalse:
        return 'TRUE OR FALSE';
      default:
        return 'QUESTION';
    }
  }
}
