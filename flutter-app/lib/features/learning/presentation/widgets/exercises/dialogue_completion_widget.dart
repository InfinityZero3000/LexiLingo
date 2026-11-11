import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 6. Dialogue Completion
// ═══════════════════════════════════════════════════════════════
class DialogueCompletionWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const DialogueCompletionWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<DialogueCompletionWidget> createState() =>
      _DialogueCompletionWidgetState();
}

class _DialogueCompletionWidgetState extends State<DialogueCompletionWidget> {
  late final TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.userAnswer ?? '');
  }

  @override
  void didUpdateWidget(covariant DialogueCompletionWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.userAnswer != oldWidget.userAnswer &&
        widget.userAnswer != _controller.text) {
      _controller.text = widget.userAnswer ?? '';
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // Parse "A: ... B: ..." into two lines
  (String, String) _parseDialogue() {
    final q = widget.exercise.question;
    final bIdx = q.indexOf(RegExp(r'\bB:'));
    if (bIdx == -1) return (q, '');
    return (
      q.substring(0, bIdx).replaceFirst(RegExp(r'^A:\s*'), '').trim(),
      q.substring(bIdx).replaceFirst(RegExp(r'^B:\s*'), '').trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final (lineA, lineB) = _parseDialogue();
    final options = widget.exercise.options ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.dialogueCompletionTitle'.tr(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          // Person A bubble (left)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.surface,
                child: Icon(
                  Icons.person_outline,
                  size: 20,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.card,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: colors.border),
                  ),
                  // The gap can sit in either speaker's line; rendering it
                  // only in B's left "A: {blank} B: ..." with no input at all.
                  child: lineA.contains('{blank}')
                      ? _buildBlankedLine(lineA)
                      : Text(
                          '"$lineA"',
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.textPrimary,
                            height: 1.4,
                          ),
                        ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Person B bubble (right) with blank
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomLeft: Radius.circular(20),
                    ),
                  ),
                  child: lineB.contains('{blank}')
                      ? _buildBlankedLine(lineB)
                      : Text(
                          lineB.isEmpty ? '[_____]' : lineB,
                          style: TextStyle(
                            fontSize: 15,
                            color: colors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              CircleAvatar(
                radius: 18,
                backgroundColor: colors.primary,
                child: Icon(Icons.person, size: 20, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...options.map((opt) {
            final sel = widget.userAnswer == opt;
            final corr = widget.exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: ExerciseOptionCard(
                text: opt,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: widget.isAnswered,
                onTap: () => widget.onAnswer(opt),
                radius: 16,
              ),
            );
          }),
          if (widget.isAnswered) ...[
            const SizedBox(height: 16),
            ExerciseExplanationCard(
              explanation: widget.exercise.explanation,
              isCorrect: widget.isCorrect ?? false,
              correctAnswer: widget.exercise.correctAnswer,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlankedLine(String line) {
    final colors = ExercisePalette.of(context);
    final parts = line.split('{blank}');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          parts[0],
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 84,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isAnswered ? colors.primary : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: colors.primary, width: 1.5),
          ),
          child: TextField(
            key: const Key('dialogue-blank-input'),
            controller: _controller,
            focusNode: _focusNode,
            enabled: !widget.isAnswered,
            textAlign: TextAlign.center,
            textInputAction: TextInputAction.done,
            onChanged: widget.onInputChanged,
            onSubmitted: (value) {
              if (widget.onInputChanged == null && value.trim().isNotEmpty) {
                widget.onAnswer(value.trim());
              }
            },
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: widget.isAnswered ? Colors.white : colors.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: '____',
              hintStyle: TextStyle(
                color: colors.primary,
                fontWeight: FontWeight.w700,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
            ),
          ),
        ),
        if (parts.length > 1)
          Text(
            parts[1],
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
      ],
    );
  }
}
