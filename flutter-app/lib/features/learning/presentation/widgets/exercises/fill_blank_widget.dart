import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

String formatFillBlankPrompt(String question, String correctAnswer) {
  if (!question.contains('{blank}')) return question;
  final words = correctAnswer.split(' ');
  final blankRep = words.map((w) => '_' * w.length).join(' ');
  return question.replaceAll('{blank}', blankRep);
}

// ═══════════════════════════════════════════════════════════════
// 3. Fill in the Blank
// ═══════════════════════════════════════════════════════════════
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
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  // Dash-style blank for text-input questions (one underscore per letter, spaced)
  Widget _buildDashPlaceholder(ExercisePalette colors) {
    final answer = widget.exercise.correctAnswer.trim();
    // Build "_ _ _" per word, words separated by two spaces
    final dashes = answer
        .split(' ')
        .map((w) {
          return List.generate(w.length.clamp(1, 12), (_) => '_').join(' ');
        })
        .join('   ');
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      child: Text(
        dashes,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.primary,
          letterSpacing: 1,
        ),
      ),
    );
  }

  // Build sentence with a highlighted slot for the blank
  Widget _buildSentence(String? selected, {bool hasOptions = true}) {
    final colors = ExercisePalette.of(context);
    final q = widget.exercise.question;
    if (!q.contains('{blank}')) {
      return Text(
        q,
        style: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: colors.textPrimary,
          height: 1.4,
        ),
      );
    }
    final parts = q.split('{blank}');
    final before = parts[0];
    final after = parts.length > 1 ? parts[1] : '';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          before,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
        if (selected != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              selected,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          )
        else if (hasOptions)
          // Choose-answer: continuous underline
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 72,
            height: 28,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colors.primary, width: 2.5),
              ),
            ),
          )
        else
          // Text-input: dash-per-letter style
          _buildDashPlaceholder(colors),
        Text(
          after,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            height: 1.4,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = widget.exercise.options;
    final hasOptions = options != null && options.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.fillBlankLabel'.tr(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'lesson.exercise.fillBlankInstruction'.tr(),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          const SizedBox(height: 20),
          // Sentence card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: colors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.border),
            ),
            child: _buildSentence(widget.userAnswer, hasOptions: hasOptions),
          ),
          const SizedBox(height: 24),
          if (hasOptions) ...[
            ...List.generate(options.length, (i) {
              final opt = options[i];
              final sel = widget.userAnswer == opt;
              final corr = widget.exercise.correctAnswer == opt;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: ExerciseOptionCard(
                  text: opt,
                  label: '${i + 1}',
                  isSelected: sel,
                  isCorrect: corr,
                  isAnswered: widget.isAnswered,
                  onTap: () => widget.onAnswer(opt),
                ),
              );
            }),
          ] else ...[
            TextField(
              controller: _ctrl,
              enabled: !widget.isAnswered,
              decoration: InputDecoration(
                hintText: 'lesson.exercise.answerHint'.tr(),
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
              onSubmitted: (v) {
                if (v.trim().isNotEmpty) widget.onAnswer(v.trim());
              },
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
                  'common.confirm'.tr(),
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
          ],
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
