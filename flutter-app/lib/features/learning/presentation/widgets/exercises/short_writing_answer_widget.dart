import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 16. Short Writing Answer
// ═══════════════════════════════════════════════════════════════
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
  State<ShortWritingAnswerWidget> createState() =>
      _ShortWritingAnswerWidgetState();
}

class _ShortWritingAnswerWidgetState extends State<ShortWritingAnswerWidget> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _extractHighlightWord() => extractQuotedWord(widget.exercise.question);

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final highlight = _extractHighlightWord();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.edit_note_rounded,
                  size: 20,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                'lesson.exercise.shortWritingTitle'.tr(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.primary,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Question with highlighted word
          RichText(
            text: TextSpan(
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
                height: 1.3,
              ),
              children: [
                TextSpan(
                  text: widget.exercise.question
                      .replaceAll('"$highlight"', '')
                      .replaceAll("'$highlight'", '')
                      .trimRight()
                      .replaceAll(RegExp(r'\s+$'), ''),
                ),
                if (highlight.isNotEmpty) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '"$highlight"',
                    style: TextStyle(color: colors.primary),
                  ),
                  const TextSpan(text: '.'),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Text area
          TextField(
            controller: _ctrl,
            enabled: !widget.isAnswered,
            maxLines: 4,
            decoration: InputDecoration(
              hintText: 'lesson.exercise.shortWritingHint'.tr(),
              hintStyle: TextStyle(color: colors.textMuted, fontSize: 14),
              filled: true,
              fillColor: colors.card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.border, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide(color: colors.primary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty) {
                  widget.onAnswer(_ctrl.text.trim());
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(999),
                ),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: Text(
                'lesson.checkAnswer'.tr(),
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
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
}
