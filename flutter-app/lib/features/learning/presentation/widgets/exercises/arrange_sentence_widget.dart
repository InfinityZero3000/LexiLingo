import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 4. Arrange the Sentence
// ═══════════════════════════════════════════════════════════════
class ArrangeSentenceWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const ArrangeSentenceWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<ArrangeSentenceWidget> createState() => _ArrangeSentenceWidgetState();
}

class _ArrangeSentenceWidgetState extends State<ArrangeSentenceWidget> {
  final List<String> _placed = [];
  late List<String> _bank;

  @override
  void initState() {
    super.initState();
    _bank = List<String>.from(widget.exercise.options ?? []);
  }

  @override
  void didUpdateWidget(ArrangeSentenceWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercise.id != oldWidget.exercise.id) {
      _placed.clear();
      _bank = List<String>.from(widget.exercise.options ?? []);
    }
  }

  // Tapping a word only drafts the in-progress order — submitting on every
  // tap would lock the exercise (isAnswered) after the first word and block
  // the rest of the bank. The learner finalizes it via the Continue button.
  void _reportDraft() {
    // Half a sentence is not an answer: an empty draft keeps the check button
    // disabled until every word in the bank is placed.
    final draft = _bank.isEmpty ? _placed.join(' ') : '';
    if (widget.onInputChanged != null) {
      widget.onInputChanged!(draft);
    } else {
      widget.onAnswer(draft);
    }
  }

  void _placeWord(String word) {
    setState(() {
      _bank.remove(word);
      _placed.add(word);
    });
    _reportDraft();
  }

  void _removeWord(String word) {
    if (widget.isAnswered) return;
    setState(() {
      _placed.remove(word);
      _bank.add(word);
    });
    _reportDraft();
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    // Graded color only applies once the exercise is answered — while the
    // learner is still arranging, the drop zone stays neutral/primary.
    final gradedColor = widget.isAnswered
        ? ((widget.isCorrect ?? false) ? kCorrect : kError)
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.arrangeSentenceTitle'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            exerciseQuote(widget.exercise.question),
            style: TextStyle(
              fontSize: 14,
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 24),
          // Drop zone (placed words) — borders and fills green/red once graded
          // so the learner sees the result at a glance, not just in the text
          // note below.
          Container(
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: gradedColor != null
                  ? gradedColor.withValues(alpha: 0.08)
                  : colors.card,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: gradedColor ?? colors.border,
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: _placed.isEmpty
                ? Center(
                    child: Text(
                      'lesson.exercise.arrangeSentenceInstruction'.tr(),
                      style: TextStyle(fontSize: 13, color: colors.textMuted),
                    ),
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (gradedColor != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                (widget.isCorrect ?? false)
                                    ? Icons.check_circle_rounded
                                    : Icons.cancel_rounded,
                                size: 18,
                                color: gradedColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                (widget.isCorrect ?? false)
                                    ? 'lesson.exercise.correctLabel'.tr()
                                    : 'lesson.exercise.incorrectLabel'.tr(),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: gradedColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _placed
                            .map(
                              (w) => GestureDetector(
                                onTap: () => _removeWord(w),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: gradedColor ?? colors.primary,
                                    borderRadius: BorderRadius.circular(999),
                                    border: Border.all(
                                      color: gradedColor ?? colors.primaryDeep,
                                    ),
                                  ),
                                  child: Text(
                                    w,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    ],
                  ),
          ),
          const SizedBox(height: 20),
          // Word bank
          if (!widget.isAnswered || _bank.isNotEmpty)
            Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _bank
                  .map(
                    (w) => GestureDetector(
                      onTap: widget.isAnswered ? null : () => _placeWord(w),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.card,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: colors.border, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: colors.shadow,
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          w,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (widget.isAnswered) ...[
            const SizedBox(height: 20),
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

String exerciseQuote(String q) {
  const prefixes = ['Arrange:', 'Sắp xếp:', 'Reorder:'];
  for (final p in prefixes) {
    if (q.startsWith(p)) return q.substring(p.length).trim();
  }
  return q;
}
