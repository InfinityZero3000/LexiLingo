import 'dart:math';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';

// ==========================================
// Helper Utility for Fill-in-the-Blank Formatting
// ==========================================
String formatFillBlankPrompt(String question, String correctAnswer) {
  if (!question.contains('{blank}')) return question;
  final words = correctAnswer.split(' ');
  final blankRep = words.map((w) => '_' * w.length).join(' ');
  return question.replaceAll('{blank}', blankRep);
}

// ==========================================
// 1. True or False Widget
// ==========================================
class TrueOrFalseWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const TrueOrFalseWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                exercise.question,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 32),
          _buildOptionCard(context, "True"),
          const SizedBox(height: 16),
          _buildOptionCard(context, "False"),
        ],
      ),
    );
  }

  Widget _buildOptionCard(BuildContext context, String option) {
    final isSelected = userAnswer == option;
    Color cardColor = Theme.of(context).cardColor;
    Color borderColor = Colors.grey[300]!;

    if (isAnswered) {
      if (option == exercise.correctAnswer) {
        cardColor = AppColors.greenSuccessBright.withValues(alpha: 0.15);
        borderColor = AppColors.greenSuccessBright;
      } else if (isSelected && !isCorrect!) {
        cardColor = AppColors.errorBright.withValues(alpha: 0.15);
        borderColor = AppColors.errorBright;
      }
    } else if (isSelected) {
      borderColor = Theme.of(context).primaryColor;
    }

    return InkWell(
      onTap: isAnswered ? null : () => onAnswer(option),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 24),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              option,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isSelected ? Theme.of(context).primaryColor : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 2. Multiple Choice Widget
// ==========================================
class MultipleChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const MultipleChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final options = exercise.options ?? [];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                exercise.question,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
              ),
            ),
          ),
          const SizedBox(height: 24),
          ...options.map((opt) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: _buildOptionCard(context, opt),
              )),
        ],
      ),
    );
  }

  Widget _buildOptionCard(BuildContext context, String option) {
    final isSelected = userAnswer == option;
    Color cardColor = Theme.of(context).cardColor;
    Color borderColor = Colors.grey[300]!;

    if (isAnswered) {
      if (option == exercise.correctAnswer) {
        cardColor = AppColors.greenSuccessBright.withValues(alpha: 0.15);
        borderColor = AppColors.greenSuccessBright;
      } else if (isSelected && !isCorrect!) {
        cardColor = AppColors.errorBright.withValues(alpha: 0.15);
        borderColor = AppColors.errorBright;
      }
    } else if (isSelected) {
      borderColor = Theme.of(context).primaryColor;
    }

    return InkWell(
      onTap: isAnswered ? null : () => onAnswer(option),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Text(
          option,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

// ==========================================
// 3. Fill in the Blank Widget
// ==========================================
class FillBlankWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const FillBlankWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<FillBlankWidget> createState() => _FillBlankWidgetState();
}

class _FillBlankWidgetState extends State<FillBlankWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formattedPrompt = formatFillBlankPrompt(widget.exercise.question, widget.exercise.correctAnswer);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Text(
                formattedPrompt,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Type your answer here...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (val) {
              if (val.trim().isNotEmpty) {
                widget.onAnswer(val.trim());
              }
            },
          ),
          const SizedBox(height: 16),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onAnswer(_controller.text.trim());
                }
              },
              child: const Text('Submit'),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 4. Arrange the Sentence Widget
// ==========================================
class ArrangeSentenceWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ArrangeSentenceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<ArrangeSentenceWidget> createState() => _ArrangeSentenceWidgetState();
}

class _ArrangeSentenceWidgetState extends State<ArrangeSentenceWidget> {
  final List<String> _selectedWords = [];
  late List<String> _shuffledWords;

  @override
  void initState() {
    super.initState();
    final words = widget.exercise.options ?? widget.exercise.correctAnswer.split(' ');
    _shuffledWords = List.from(words)..shuffle();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Arrange the words to form a correct sentence:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          // Target Area
          Container(
            constraints: const BoxConstraints(minHeight: 100),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey[300]!),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _selectedWords.map((word) => _buildWordChip(word, isSelected: true)).toList(),
            ),
          ),
          const SizedBox(height: 32),
          // Available words
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _shuffledWords.map((word) => _buildWordChip(word, isSelected: false)).toList(),
          ),
          const Spacer(),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: _selectedWords.isEmpty
                  ? null
                  : () {
                      widget.onAnswer(_selectedWords.join(' '));
                    },
              child: const Text('Check Sentence'),
            ),
        ],
      ),
    );
  }

  Widget _buildWordChip(String word, {required bool isSelected}) {
    return ActionChip(
      label: Text(word),
      onPressed: widget.isAnswered
          ? null
          : () {
              setState(() {
                if (isSelected) {
                  _selectedWords.remove(word);
                  _shuffledWords.add(word);
                } else {
                  _shuffledWords.remove(word);
                  _selectedWords.add(word);
                }
              });
            },
    );
  }
}

// ==========================================
// 5. Translation Choice Widget
// ==========================================
class TranslationChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const TranslationChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceWidget(
      exercise: exercise,
      onAnswer: onAnswer,
      isAnswered: isAnswered,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );
  }
}

// ==========================================
// 6. Dialogue Completion Widget
// ==========================================
class DialogueCompletionWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const DialogueCompletionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<DialogueCompletionWidget> createState() => _DialogueCompletionWidgetState();
}

class _DialogueCompletionWidgetState extends State<DialogueCompletionWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formattedPrompt = formatFillBlankPrompt(widget.exercise.question, widget.exercise.correctAnswer);
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Simulated Dialogue Bubbles
          _buildBubble(context, "Speaker A", "Hi there, can you help me?", isSpeakerA: true),
          const SizedBox(height: 12),
          _buildBubble(context, "Speaker B", formattedPrompt, isSpeakerA: false),
          const SizedBox(height: 32),
          TextField(
            controller: _controller,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Type missing dialogue...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const Spacer(),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onAnswer(_controller.text.trim());
                }
              },
              child: const Text('Complete Dialogue'),
            ),
        ],
      ),
    );
  }

  Widget _buildBubble(BuildContext context, String speaker, String text, {required bool isSpeakerA}) {
    return Align(
      alignment: isSpeakerA ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
        decoration: BoxDecoration(
          color: isSpeakerA ? Colors.grey[200] : Theme.of(context).primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              speaker,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 4),
            Text(text, style: const TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 7. Collocation Choice Widget
// ==========================================
class CollocationChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CollocationChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return MultipleChoiceWidget(
      exercise: exercise,
      onAnswer: onAnswer,
      isAnswered: isAnswered,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );
  }
}

// ==========================================
// 8. Dictation Widget
// ==========================================
class DictationWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const DictationWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<DictationWidget> createState() => _DictationWidgetState();
}

class _DictationWidgetState extends State<DictationWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpeakIconButton(
                text: widget.exercise.correctAnswer,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 24),
          const Text(
            'Listen carefully and write what you hear:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Type text here...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 24),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onAnswer(_controller.text.trim());
                }
              },
              child: const Text('Check Spelling'),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 9. Grammar Correction Widget
// ==========================================
class GrammarCorrectionWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const GrammarCorrectionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<GrammarCorrectionWidget> createState() => _GrammarCorrectionWidgetState();
}

class _GrammarCorrectionWidgetState extends State<GrammarCorrectionWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Correct the grammar mistakes in this sentence:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          Card(
            color: Colors.amber.withValues(alpha: 0.1),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                widget.exercise.question,
                style: const TextStyle(fontSize: 18, decoration: TextDecoration.lineThrough, color: Colors.red),
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Type correct sentence...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const Spacer(),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onAnswer(_controller.text.trim());
                }
              },
              child: const Text('Submit Correction'),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 10. Image Based Choice Widget
// ==========================================
class ImageBasedChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ImageBasedChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    final options = exercise.options ?? [];
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            exercise.question,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: GridView.count(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              children: options.map((opt) => _buildImageOption(context, opt)).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildImageOption(BuildContext context, String option) {
    final isSelected = userAnswer == option;
    Color cardColor = Theme.of(context).cardColor;
    Color borderColor = Colors.grey[300]!;

    if (isAnswered) {
      if (option == exercise.correctAnswer) {
        cardColor = AppColors.greenSuccessBright.withValues(alpha: 0.15);
        borderColor = AppColors.greenSuccessBright;
      } else if (isSelected && !isCorrect!) {
        cardColor = AppColors.errorBright.withValues(alpha: 0.15);
        borderColor = AppColors.errorBright;
      }
    } else if (isSelected) {
      borderColor = Theme.of(context).primaryColor;
    }

    return InkWell(
      onTap: isAnswered ? null : () => onAnswer(option),
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor, width: 2),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.image, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            Text(option, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }
}

// ==========================================
// 11. Listen and Choose Widget
// ==========================================
class ListeningChoiceWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ListeningChoiceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SpeakIconButton(
                text: exercise.correctAnswer,
                size: 64,
                color: Theme.of(context).primaryColor,
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Listen and select the correct matching audio phrase:',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: MultipleChoiceWidget(
              exercise: exercise,
              onAnswer: onAnswer,
              isAnswered: isAnswered,
              userAnswer: userAnswer,
              isCorrect: isCorrect,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 12. Match Word to Meaning Widget
// ==========================================
class MatchWordMeaningWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const MatchWordMeaningWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<MatchWordMeaningWidget> createState() => _MatchWordMeaningWidgetState();
}

class _MatchWordMeaningWidgetState extends State<MatchWordMeaningWidget> {
  String? _selectedLeft;
  String? _selectedRight;
  final Map<String, String> _matches = {};

  @override
  Widget build(BuildContext context) {
    final options = widget.exercise.options ?? [];
    final leftList = options.take(options.length ~/ 2).toList();
    final rightList = options.skip(options.length ~/ 2).toList();

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Match the words on the left with meanings on the right:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          Expanded(
            child: Row(
              children: [
                // Left Column
                Expanded(
                  child: ListView(
                    children: leftList.map((item) => _buildChip(item, isLeft: true)).toList(),
                  ),
                ),
                const SizedBox(width: 24),
                // Right Column
                Expanded(
                  child: ListView(
                    children: rightList.map((item) => _buildChip(item, isLeft: false)).toList(),
                  ),
                ),
              ],
            ),
          ),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: _matches.isEmpty
                  ? null
                  : () {
                      final answerStr = _matches.entries.map((e) => "${e.key}:${e.value}").join(', ');
                      widget.onAnswer(answerStr);
                    },
              child: const Text('Verify Matches'),
            ),
        ],
      ),
    );
  }

  Widget _buildChip(String text, {required bool isLeft}) {
    final isSelected = isLeft ? _selectedLeft == text : _selectedRight == text;
    final isMatched = isLeft ? _matches.containsKey(text) : _matches.containsValue(text);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: ChoiceChip(
        label: Text(text),
        selected: isSelected || isMatched,
        onSelected: widget.isAnswered || isMatched
            ? null
            : (val) {
                setState(() {
                  if (isLeft) {
                    _selectedLeft = val ? text : null;
                  } else {
                    _selectedRight = val ? text : null;
                  }
                  if (_selectedLeft != null && _selectedRight != null) {
                    _matches[_selectedLeft!] = _selectedRight!;
                    _selectedLeft = null;
                    _selectedRight = null;
                  }
                });
              },
      ),
    );
  }
}

// ==========================================
// 13. Vocabulary Flashcard Widget
// ==========================================
class VocabularyFlashcardWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const VocabularyFlashcardWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<VocabularyFlashcardWidget> createState() => _VocabularyFlashcardWidgetState();
}

class _VocabularyFlashcardWidgetState extends State<VocabularyFlashcardWidget> {
  bool _showBack = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flip Card Animation Container
          GestureDetector(
            onTap: () {
              setState(() {
                _showBack = !_showBack;
              });
            },
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.0, end: _showBack ? pi : 0.0),
              duration: const Duration(milliseconds: 400),
              builder: (context, val, child) {
                final isBack = val >= pi / 2;
                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001)
                    ..rotateY(val),
                  alignment: Alignment.center,
                  child: Container(
                    height: 300,
                    decoration: BoxDecoration(
                      color: isBack ? Colors.teal[50] : Theme.of(context).cardColor,
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 15)],
                      border: Border.all(color: Colors.grey[300]!, width: 2),
                    ),
                    child: Center(
                      child: isBack
                          ? Transform(
                              transform: Matrix4.identity()..rotateY(pi),
                              alignment: Alignment.center,
                              child: Padding(
                                padding: const EdgeInsets.all(24.0),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      widget.exercise.explanation ?? 'Definition detail',
                                      style: const TextStyle(fontSize: 18, height: 1.4),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 16),
                                    const Text('(Tap card to flip back)', style: TextStyle(color: Colors.grey)),
                                  ],
                                ),
                              ),
                            )
                          : Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    widget.exercise.question,
                                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 16),
                                  const Text('(Tap card to flip definition)', style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 48),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () => widget.onAnswer("Got it!"),
              child: const Text("I've learned this word!"),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 14. Pronunciation Practice Widget
// ==========================================
class PronunciationPracticeWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const PronunciationPracticeWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<PronunciationPracticeWidget> createState() => _PronunciationPracticeWidgetState();
}

class _PronunciationPracticeWidgetState extends State<PronunciationPracticeWidget> {
  bool _isRecording = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Listen and practice speaking this phrase:',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          Text(
            widget.exercise.correctAnswer,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 48),
          IconButton(
            icon: Icon(
              _isRecording ? Icons.mic : Icons.mic_none,
              size: 72,
              color: _isRecording ? Colors.red : Theme.of(context).primaryColor,
            ),
            onPressed: widget.isAnswered
                ? null
                : () {
                    setState(() {
                      _isRecording = !_isRecording;
                    });
                    if (!_isRecording) {
                      widget.onAnswer(widget.exercise.correctAnswer);
                    }
                  },
          ),
          Text(
            _isRecording ? 'Listening... Tap again to finish' : 'Tap to start speaking',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.grey),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 15. Reading Comprehension Widget
// ==========================================
class ReadingComprehensionWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ReadingComprehensionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Expanded(
            flex: 2,
            child: SingleChildScrollView(
              child: Card(
                color: Colors.blueGrey[50],
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Text(
                    exercise.explanation ?? 'Reading Passage Text Placeholder.',
                    style: const TextStyle(fontSize: 15, height: 1.5),
                  ),
                ),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            flex: 3,
            child: MultipleChoiceWidget(
              exercise: exercise,
              onAnswer: onAnswer,
              isAnswered: isAnswered,
              userAnswer: userAnswer,
              isCorrect: isCorrect,
            ),
          ),
        ],
      ),
    );
  }
}

// ==========================================
// 16. Short Writing Answer Widget
// ==========================================
class ShortWritingAnswerWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ShortWritingAnswerWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<ShortWritingAnswerWidget> createState() => _ShortWritingAnswerWidgetState();
}

class _ShortWritingAnswerWidgetState extends State<ShortWritingAnswerWidget> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            widget.exercise.question,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            maxLines: 4,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Type translation or short response...',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const Spacer(),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_controller.text.trim().isNotEmpty) {
                  widget.onAnswer(_controller.text.trim());
                }
              },
              child: const Text('Submit Answer'),
            ),
        ],
      ),
    );
  }
}

// ==========================================
// 17. Speaking Repeat Widget
// ==========================================
class SpeakingRepeatWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const SpeakingRepeatWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return PronunciationPracticeWidget(
      exercise: exercise,
      onAnswer: onAnswer,
      isAnswered: isAnswered,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );
  }
}

// ==========================================
// 18. Categorization Widget
// ==========================================
class CategorizationWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CategorizationWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return MatchWordMeaningWidget(
      exercise: exercise,
      onAnswer: onAnswer,
      isAnswered: isAnswered,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );
  }
}

// ==========================================
// 19. Cognitive Fluidity Widget
// ==========================================
class CognitiveFluidityWidget extends StatelessWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CognitiveFluidityWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  Widget build(BuildContext context) {
    return MatchWordMeaningWidget(
      exercise: exercise,
      onAnswer: onAnswer,
      isAnswered: isAnswered,
      userAnswer: userAnswer,
      isCorrect: isCorrect,
    );
  }
}
