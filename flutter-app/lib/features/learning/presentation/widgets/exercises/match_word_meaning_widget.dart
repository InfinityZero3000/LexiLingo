import 'dart:math';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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

/// One hue per left-hand word, so a pair stays recognisable by colour even
/// where its line crosses another. Kept away from the red/green used to grade.
const _pairHues = <double>[212, 268, 300, 28, 186, 45];

Color _pairColor(int leftIndex) => HSLColor.fromAHSL(
  1,
  _pairHues[leftIndex % _pairHues.length],
  0.55,
  0.40,
).toColor();

class _MatchWordMeaningWidgetState extends State<MatchWordMeaningWidget> {
  String? _selectedLeft;
  String? _selectedRight;
  final Map<String, String> _matched = {};
  late List<String> _left;
  late List<String> _right;
  final _boardKey = GlobalKey();
  late Map<String, GlobalKey> _leftKeys;
  late Map<String, GlobalKey> _rightKeys;

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
      _selectedRight = null;
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
    _leftKeys = {for (final w in _left) w: GlobalKey()};
    _rightKeys = {for (final w in _right) w: GlobalKey()};
  }

  // Draft, not submit — onAnswer would lock the exercise (isAnswered) after
  // the first match. A partial set of pairs is never an answer: an empty
  // draft keeps the check button disabled until all are matched.
  void _reportDraft() {
    final ans = _matched.length < _left.length
        ? ''
        : _matched.entries.map((e) => '${e.key}:${e.value}').join(', ');
    if (widget.onInputChanged != null) {
      widget.onInputChanged!(ans);
    } else {
      widget.onAnswer(ans);
    }
  }

  String? _leftOf(String right) {
    for (final e in _matched.entries) {
      if (e.value == right) return e.key;
    }
    return null;
  }

  void _pair(String left, String right) {
    setState(() {
      _matched[left] = right;
      _selectedLeft = null;
      _selectedRight = null;
    });
    _reportDraft();
  }

  // Tapping a matched word undoes that pair, so a wrong match can be fixed
  // before checking. Either side can be picked first.
  void _tapLeft(String item) {
    if (widget.isAnswered) return;
    if (_matched.containsKey(item)) {
      setState(() => _matched.remove(item));
      _reportDraft();
    } else if (_selectedRight != null) {
      _pair(item, _selectedRight!);
    } else {
      setState(() => _selectedLeft = _selectedLeft == item ? null : item);
    }
  }

  void _tapRight(String item) {
    if (widget.isAnswered) return;
    final owner = _leftOf(item);
    if (owner != null) {
      setState(() => _matched.remove(owner));
      _reportDraft();
    } else if (_selectedLeft != null) {
      _pair(_selectedLeft!, item);
    } else {
      setState(() => _selectedRight = _selectedRight == item ? null : item);
    }
  }

  Widget _pill({
    required Key key,
    required String text,
    required Color? fill,
    required bool highlighted,
    required VoidCallback? onTap,
    required ExercisePalette colors,
  }) {
    final filled = fill != null || highlighted;
    final color = fill ?? (highlighted ? colors.primary : colors.card);
    return Semantics(
      button: true,
      selected: highlighted,
      label: text,
      // excludeSemantics also drops the child's tap action.
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          constraints: const BoxConstraints(minHeight: 48),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(
              color: filled ? color : colors.border,
              width: AppBorderWidth.regular,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.shadow,
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge!.copyWith(
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : colors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = ExercisePalette.of(context);
    // Only known once graded — before that, a matched pair is just "filled
    // in" (its own colour), not yet right or wrong.
    final correctMap = widget.isAnswered
        ? parsePairAnswer(widget.exercise.correctAnswer)
        : const <String, String>{};

    Color linkColor(String left) => widget.isAnswered
        ? (correctMap[left] == _matched[left] ? kCorrect : kError)
        : _pairColor(_left.indexOf(left));

    final rows = max(_left.length, _right.length);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, AppSpacing.xl, 20, AppSpacing.lg),
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
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: LayoutBuilder(
                builder: (context, box) {
                  // Wide enough between the columns for the lines to be seen.
                  final gap = (box.maxWidth * 0.16).clamp(28.0, 72.0);
                  return CustomPaint(
                    key: _boardKey,
                    painter: _PairLinkPainter(
                      board: _boardKey,
                      leftKeys: _leftKeys,
                      rightKeys: _rightKeys,
                      matched: _matched,
                      colorOf: linkColor,
                    ),
                    child: Column(
                      children: [
                        for (var i = 0; i < rows; i++)
                          Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.md,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: i < _left.length
                                      ? _leftPill(_left[i], colors, linkColor)
                                      : const SizedBox.shrink(),
                                ),
                                SizedBox(width: gap),
                                Expanded(
                                  child: i < _right.length
                                      ? _rightPill(_right[i], colors, linkColor)
                                      : const SizedBox.shrink(),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Instruction hint
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: colors.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'lesson.exercise.matchPairsInstruction'.tr(),
                    style: Theme.of(context).textTheme.bodySmall!.copyWith(
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

  Widget _leftPill(
    String item,
    ExercisePalette colors,
    Color Function(String) linkColor,
  ) {
    final matched = _matched.containsKey(item);
    return _pill(
      key: _leftKeys[item]!,
      text: item,
      fill: matched ? linkColor(item) : null,
      highlighted: _selectedLeft == item,
      onTap: widget.isAnswered ? null : () => _tapLeft(item),
      colors: colors,
    );
  }

  Widget _rightPill(
    String item,
    ExercisePalette colors,
    Color Function(String) linkColor,
  ) {
    final owner = _leftOf(item);
    return _pill(
      key: _rightKeys[item]!,
      text: item,
      fill: owner == null ? null : linkColor(owner),
      highlighted: _selectedRight == item,
      onTap: widget.isAnswered ? null : () => _tapRight(item),
      colors: colors,
    );
  }
}

/// Draws one curved line from each matched word to its meaning, behind the
/// pills. Positions are read from the pills' own render boxes at paint time, so
/// they are always the laid-out ones.
class _PairLinkPainter extends CustomPainter {
  final GlobalKey board;
  final Map<String, GlobalKey> leftKeys;
  final Map<String, GlobalKey> rightKeys;
  final Map<String, String> matched;
  final Color Function(String left) colorOf;

  _PairLinkPainter({
    required this.board,
    required this.leftKeys,
    required this.rightKeys,
    required this.matched,
    required this.colorOf,
  });

  RenderBox? _box(GlobalKey key) {
    final object = key.currentContext?.findRenderObject();
    return object is RenderBox && object.attached && object.hasSize
        ? object
        : null;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final boardBox = _box(board);
    if (boardBox == null) return;
    for (final pair in matched.entries) {
      final l = _box(leftKeys[pair.key] ?? GlobalKey());
      final r = _box(rightKeys[pair.value] ?? GlobalKey());
      if (l == null || r == null) continue;
      final start = boardBox.globalToLocal(
        l.localToGlobal(Offset(l.size.width, l.size.height / 2)),
      );
      final end = boardBox.globalToLocal(
        r.localToGlobal(Offset(0, r.size.height / 2)),
      );
      final bend = (end.dx - start.dx) / 2;
      final paint = Paint()
        ..color = colorOf(pair.key)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round;
      canvas.drawPath(
        Path()
          ..moveTo(start.dx, start.dy)
          ..cubicTo(
            start.dx + bend,
            start.dy,
            end.dx - bend,
            end.dy,
            end.dx,
            end.dy,
          ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PairLinkPainter old) => true;
}
