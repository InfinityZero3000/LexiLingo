import 'dart:math';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

// ═══════════════════════════════════════════════════════════════
// 18. Categorization (Phân loại từ vựng)
// ═══════════════════════════════════════════════════════════════
class CategorizationWidget extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final ValueChanged<String>? onInputChanged;
  final bool isAnswered;
  final String? userAnswer;
  final bool? isCorrect;

  const CategorizationWidget({
    super.key,
    required this.exercise,
    required this.onAnswer,
    this.onInputChanged,
    required this.isAnswered,
    this.userAnswer,
    this.isCorrect,
  });

  @override
  State<CategorizationWidget> createState() => _CategorizationWidgetState();
}

class _CategorizationWidgetState extends State<CategorizationWidget> {
  String? _selectedWord;
  final Map<String, String> _assignments = {}; // word → category

  @override
  void initState() {
    super.initState();
    _parseUserAnswer();
  }

  @override
  void didUpdateWidget(CategorizationWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Unanswered, the widget's own picks are the truth — an empty draft for a
    // partial set must not wipe them.
    if (widget.isAnswered && widget.userAnswer != oldWidget.userAnswer) {
      _parseUserAnswer();
    }
  }

  void _parseUserAnswer() {
    _assignments.clear();
    final ans = widget.userAnswer;
    if (ans != null && ans.isNotEmpty) {
      final pairs = ans.split(',');
      for (final pair in pairs) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          _assignments[parts[0].trim()] = parts[1].trim();
        }
      }
    }
  }

  void _updateAnswer() {
    final total = (widget.exercise.options?.length ?? 0) ~/ 2;
    final ans = _assignments.length < total
        ? ''
        : _assignments.entries.map((e) => '${e.key}:${e.value}').join(', ');
    if (widget.onInputChanged != null) {
      widget.onInputChanged!(ans);
    } else {
      widget.onAnswer(ans);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    final options = widget.exercise.options ?? [];
    final half = options.length ~/ 2;
    // Word i belongs to category i in the stored content — shuffle the bank so
    // the buckets can't be filled top-to-bottom without reading. Seeded by
    // exercise id: same order on every rebuild.
    final words = options.take(half).toList()
      ..shuffle(Random(widget.exercise.id.hashCode));
    // One category per word in storage ("fruit, fruit, animal") — one bucket
    // per category on screen.
    final cats = options.skip(half).toSet().toList();

    final unassigned = words
        .where((w) => !_assignments.containsKey(w))
        .toList();
    // Only known once graded — before that, an assigned word is just
    // "placed" (neutral), not yet right or wrong.
    final correctMap = widget.isAnswered
        ? parsePairAnswer(widget.exercise.correctAnswer)
        : const <String, String>{};

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.categorizationTitle'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: colors.textPrimary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'lesson.exercise.categorizationInstruction'.tr(),
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Category buckets
          ...List.generate(cats.length, (ci) {
            final cat = cats[ci];
            final assigned = _assignments.entries
                .where((e) => e.value == cat)
                .map((e) => e.key)
                .toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DragTarget<String>(
                onWillAcceptWithDetails: (details) => !widget.isAnswered,
                onAcceptWithDetails: (details) {
                  final word = details.data;
                  setState(() {
                    _assignments[word] = cat;
                    if (_selectedWord == word) {
                      _selectedWord = null;
                    }
                  });
                  _updateAnswer();
                },
                builder: (context, candidateData, rejectedData) {
                  final isHovered = candidateData.isNotEmpty;
                  return GestureDetector(
                    onTap: widget.isAnswered || _selectedWord == null
                        ? null
                        : () {
                            setState(() {
                              _assignments[_selectedWord!] = cat;
                              _selectedWord = null;
                            });
                            _updateAnswer();
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(14),
                      constraints: const BoxConstraints(minHeight: 72),
                      decoration: BoxDecoration(
                        color:
                            (_selectedWord != null || isHovered) &&
                                !widget.isAnswered
                            ? colors.primary.withValues(alpha: 0.06)
                            : colors.card,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color:
                              (_selectedWord != null || isHovered) &&
                                  !widget.isAnswered
                              ? colors.primary
                              : colors.border,
                          width: 1.5,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                ci == 0
                                    ? Icons.category_outlined
                                    : Icons.bolt_outlined,
                                size: 18,
                                color: ci == 0
                                    ? colors.primary
                                    : const Color(0xFF00A86B),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                cat.toUpperCase(),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: ci == 0
                                      ? colors.primary
                                      : const Color(0xFF00A86B),
                                  letterSpacing: 1.1,
                                ),
                              ),
                            ],
                          ),
                          if (assigned.isNotEmpty) ...[
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: assigned.map((w) {
                                final graded = widget.isAnswered
                                    ? (correctMap[w] == cat ? kCorrect : kError)
                                    : null;
                                return GestureDetector(
                                  onTap: widget.isAnswered
                                      ? null
                                      : () {
                                          setState(() {
                                            _assignments.remove(w);
                                          });
                                          _updateAnswer();
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 7,
                                    ),
                                    decoration: BoxDecoration(
                                      color: graded != null
                                          ? graded.withValues(alpha: 0.14)
                                          : colors.surface,
                                      borderRadius: BorderRadius.circular(999),
                                      border: graded != null
                                          ? Border.all(color: graded)
                                          : null,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (graded != null) ...[
                                          Icon(
                                            graded == kCorrect
                                                ? Icons.check_rounded
                                                : Icons.close_rounded,
                                            size: 14,
                                            color: graded,
                                          ),
                                          const SizedBox(width: 4),
                                        ],
                                        Text(
                                          w,
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: graded ?? colors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              ),
            );
          }),
          const SizedBox(height: 8),
          // Word bank (unassigned)
          if (unassigned.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: unassigned.map((w) {
                  final sel = _selectedWord == w;
                  final cardChild = AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    decoration: BoxDecoration(
                      color: sel ? colors.primary : colors.card,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(
                        color: sel ? colors.primary : colors.border,
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
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.drag_indicator,
                          size: 14,
                          color: sel ? Colors.white : colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          w,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: sel ? Colors.white : colors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  );

                  final cardWidget = GestureDetector(
                    onTap: widget.isAnswered
                        ? null
                        : () => setState(() => _selectedWord = sel ? null : w),
                    child: cardChild,
                  );

                  if (widget.isAnswered) {
                    return cardWidget;
                  }

                  return Draggable<String>(
                    data: w,
                    feedback: Material(
                      color: Colors.transparent,
                      child: Opacity(opacity: 0.85, child: cardChild),
                    ),
                    childWhenDragging: Opacity(opacity: 0.3, child: cardChild),
                    child: cardWidget,
                  );
                }).toList(),
              ),
            ),
          ],
          if (widget.isAnswered) ...[
            const SizedBox(height: 16),
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
