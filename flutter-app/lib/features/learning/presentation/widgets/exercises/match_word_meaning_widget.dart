import 'dart:math';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 12. Match Word to Meaning
// ═══════════════════════════════════════════════════════════════
class MatchWordMeaningWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const MatchWordMeaningWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<MatchWordMeaningWidget> createState() => _MatchWordMeaningWidgetState();
}

class _MatchWordMeaningWidgetState extends State<MatchWordMeaningWidget> {
  String? _selectedLeft;
  final Map<String, String> _matched = {};
  late List<String> _left;
  late List<String> _right;

  @override
  void initState() {
    super.initState();
    _splitColumns();
  }

  @override
  void didUpdateWidget(MatchWordMeaningWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.exercise.id != oldWidget.exercise.id) {
      _matched.clear();
      _selectedLeft = null;
      _splitColumns();
    }
  }

  /// Content stores the pairs aligned (first half keys, second half values), so
  /// an unshuffled right column is solvable by tapping row i ↔ row i.
  /// Seeded by exercise id so the order is stable across rebuilds.
  void _splitColumns() {
    final options = widget.exercise.options ?? [];
    final half = options.length ~/ 2;
    _left = options.take(half).toList();
    _right = options.skip(half).toList()
      ..shuffle(Random(widget.exercise.id.hashCode));
  }

  // Draft, not submit — onAnswer would lock the exercise (isAnswered) after
  // the first match. A partial set of pairs is never an answer: an empty
  // draft keeps the check button disabled until all are matched.
  void _reportDraft(int total) {
    final ans = _matched.length < total
        ? ''
        : _matched.entries.map((e) => '${e.key}:${e.value}').join(', ');
    if (widget.onInputChanged != null) {
      widget.onInputChanged!(ans);
    } else {
      widget.onAnswer(ans);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final left = _left;
    final right = _right;
    // Only known once graded — before that, a matched pair is just "filled
    // in" (blue/primary), not yet right or wrong.
    final correctMap = widget.isAnswered
        ? parsePairAnswer(widget.exercise.correctAnswer)
        : const <String, String>{};

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.matchPairsTitle'.tr(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          // 2-column matching grid
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left column
                Expanded(
                  child: Column(
                    children: left.map((item) {
                      final isMatchedLeft = _matched.containsKey(item);
                      final isSelected = _selectedLeft == item;
                      final pairColor = !isMatchedLeft
                          ? null
                          : widget.isAnswered
                          ? (correctMap[item] == _matched[item]
                                ? kCorrect
                                : kError)
                          : colors.primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          // Tapping a matched word undoes that pair, so a
                          // wrong match can be fixed before checking.
                          onTap: widget.isAnswered
                              ? null
                              : isMatchedLeft
                              ? () {
                                  setState(() => _matched.remove(item));
                                  _reportDraft(left.length);
                                }
                              : () {
                                  setState(() {
                                    _selectedLeft = isSelected ? null : item;
                                  });
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color:
                                  pairColor ??
                                  (isSelected ? colors.primary : colors.card),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color:
                                    pairColor ??
                                    (isSelected
                                        ? colors.primary
                                        : colors.border),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              item,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: (isMatchedLeft || isSelected)
                                    ? Colors.white
                                    : colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(width: 12),
                // Right column
                Expanded(
                  child: Column(
                    children: right.map((item) {
                      final isMatchedRight = _matched.containsValue(item);
                      String? matchedLeft;
                      for (final e in _matched.entries) {
                        if (e.value == item) {
                          matchedLeft = e.key;
                          break;
                        }
                      }
                      final pairColor = !isMatchedRight
                          ? null
                          : widget.isAnswered
                          ? (correctMap[matchedLeft] == item
                                ? kCorrect
                                : kError)
                          : colors.primary;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: widget.isAnswered || isMatchedRight
                              ? null
                              : () {
                                  if (_selectedLeft != null) {
                                    setState(() {
                                      _matched[_selectedLeft!] = item;
                                      _selectedLeft = null;
                                    });
                                    _reportDraft(left.length);
                                  }
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              color: pairColor ?? colors.card,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: pairColor ?? colors.border,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: colors.shadow,
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              item,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: isMatchedRight
                                    ? Colors.white
                                    : colors.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
          ),
          // Instruction hint
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: colors.primary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'lesson.exercise.matchPairsInstruction'.tr(),
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (widget.isAnswered) ...[
            const SizedBox(height: 12),
            ExerciseExplanationCard(
              explanation: widget.exercise.explanation,
              isCorrect: widget.isCorrect ?? false,
              correctAnswer: widget.exercise.correctAnswer,
              pairAnswer: true,
            ),
          ],
        ],
      ),
    );
  }
}
