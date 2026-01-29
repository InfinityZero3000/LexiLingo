import 'package:flutter/material.dart';
import '../../domain/entities/lesson_entity.dart';

/// Lesson Content Widget for Fill in Blank and Translation exercises
class LessonContentWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onSubmit;
  final bool isAnswered;
  final bool? isCorrect;

  const LessonContentWidget({
    Key? key,
    required this.exercise,
    required this.onSubmit,
    this.isAnswered = false,
    this.isCorrect,
  }) : super(key: key);

  @override
  State<LessonContentWidget> createState() => _LessonContentWidgetState();
}

class _LessonContentWidgetState extends State<LessonContentWidget> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void didUpdateWidget(LessonContentWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercise != oldWidget.exercise) {
      _controller.clear();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Question Card
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
                    _getExerciseTypeLabel(),
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.exercise.question,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  
                  // Show hint if available
                  if (widget.exercise.hint != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
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
                                height: 1.4,
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
          
          // Answer Input Field
          TextField(
            controller: _controller,
            focusNode: _focusNode,
            enabled: !widget.isAnswered,
            maxLines: widget.exercise.type == ExerciseType.translate ? 3 : 1,
            decoration: InputDecoration(
              hintText: widget.exercise.type == ExerciseType.translate
                  ? 'Type your translation here...'
                  : 'Fill in the blank...',
              filled: true,
              fillColor: widget.isAnswered
                  ? (widget.isCorrect! ? Colors.green : Colors.red)
                      .withOpacity(0.1)
                  : Colors.grey[50],
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey[300]!,
                  width: 2,
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Colors.grey[300]!,
                  width: 2,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: Theme.of(context).primaryColor,
                  width: 2,
                ),
              ),
              disabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: widget.isAnswered
                      ? (widget.isCorrect! ? Colors.green : Colors.red)
                      : Colors.grey[300]!,
                  width: 2,
                ),
              ),
              suffixIcon: widget.isAnswered
                  ? Icon(
                      widget.isCorrect! ? Icons.check_circle : Icons.cancel,
                      color: widget.isCorrect! ? Colors.green : Colors.red,
                    )
                  : null,
            ),
            style: const TextStyle(fontSize: 16),
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (value) {
              if (!widget.isAnswered && value.trim().isNotEmpty) {
                widget.onSubmit(value.trim());
              }
            },
          ),
          
          const SizedBox(height: 16),
          
          // Submit Button
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                final answer = _controller.text.trim();
                if (answer.isNotEmpty) {
                  widget.onSubmit(answer);
                  _focusNode.unfocus();
                }
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                'Check Answer',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          
          // Result and Explanation
          if (widget.isAnswered) ...[
            const SizedBox(height: 24),
            Card(
              color: widget.isCorrect! 
                  ? Colors.green.withOpacity(0.1)
                  : Colors.orange.withOpacity(0.1),
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
                    
                    if (!widget.isCorrect!) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Correct answer:',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.grey[700],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.exercise.correctAnswer,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                    
                    if (widget.exercise.explanation != null) ...[
                      const SizedBox(height: 12),
                      const Divider(),
                      const SizedBox(height: 8),
                      Text(
                        widget.exercise.explanation!,
                        style: const TextStyle(fontSize: 14, height: 1.5),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getExerciseTypeLabel() {
    switch (widget.exercise.type) {
      case ExerciseType.fillInBlank:
        return 'FILL IN THE BLANK';
      case ExerciseType.translate:
        return 'TRANSLATION';
      default:
        return 'EXERCISE';
    }
  }
}
