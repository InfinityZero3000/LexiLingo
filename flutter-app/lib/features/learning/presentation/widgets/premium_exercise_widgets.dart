import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';

// ═══════════════════════════════════════════════════════════════
// Design tokens — matches flutter-app/template/cognitive_fluidity/DESIGN.md
// ═══════════════════════════════════════════════════════════════
const _kPrimary    = Color(0xFF1A73E8);
const _kPrimaryDk  = Color(0xFF005BBF); // ignore: unused_element
const _kCard       = Colors.white;
const _kSurface    = Color(0xFFE8EFFF);
const _kCorrect    = Color(0xFF2DBD73);
const _kError      = Color(0xFFE53935);
const _kBorder     = Color(0xFFCDD8F6);
const _kTextDark   = Color(0xFF141B2B);
const _kTextMid    = Color(0xFF414754);
const _kTextLight  = Color(0xFF9AA5BB);

// ═══════════════════════════════════════════════════════════════
// Shared helpers
// ═══════════════════════════════════════════════════════════════

/// Small pill label (e.g. "MULTIPLE CHOICE")
class _Badge extends StatelessWidget {
  final String label;
  final IconData? icon;
  const _Badge(this.label, {this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: _kPrimary),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: _kPrimary,
                letterSpacing: 1.1,
              ),
            ),
          ],
        ),
      );
}

/// Rounded option card (pill or rect)
class _OptionCard extends StatelessWidget {
  final String text;
  final String? label;      // letter or number shown on left/right
  final bool labelOnRight;
  final bool showRadio;     // radio circle on right
  final bool isSelected;
  final bool isCorrect;     // only meaningful when isAnswered
  final bool isAnswered;
  final VoidCallback? onTap;
  final double radius;

  const _OptionCard({
    required this.text,
    this.label,
    this.labelOnRight = false,
    this.showRadio = false,
    required this.isSelected,
    required this.isCorrect,
    required this.isAnswered,
    this.onTap,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    Color bg     = _kCard;
    Color border = _kBorder;
    Color fg     = _kTextDark;

    if (isAnswered && isSelected) {
      if (isCorrect) {
        bg = _kCorrect; border = _kCorrect; fg = Colors.white;
      } else {
        bg = _kError; border = _kError; fg = Colors.white;
      }
    } else if (!isAnswered && isSelected) {
      bg = _kPrimary; border = _kPrimary; fg = Colors.white;
    }

    final labelWidget = label == null
        ? null
        : Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              border: Border.all(
                color: isSelected ? fg.withValues(alpha: 0.5) : _kBorder,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              label!,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: isSelected ? fg : _kTextMid,
              ),
            ),
          );

    return GestureDetector(
      onTap: isAnswered ? null : onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: border, width: 1.5),
          boxShadow: isAnswered
              ? []
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 3),
                  )
                ],
        ),
        child: Row(
          children: [
            if (!labelOnRight && labelWidget != null) ...[
              labelWidget,
              const SizedBox(width: 14),
            ],
            Expanded(
              child: Text(
                text,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: fg,
                ),
              ),
            ),
            if (labelOnRight && labelWidget != null) ...[
              const SizedBox(width: 14),
              labelWidget,
            ],
            if (showRadio) ...[
              const SizedBox(width: 10),
              Icon(
                isSelected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                size: 22,
                color: isSelected ? fg : _kBorder,
              ),
            ],
            if (isAnswered && isSelected)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Icon(
                  isCorrect ? Icons.check_circle_outline : Icons.cancel_outlined,
                  size: 20,
                  color: fg,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Explanation panel shown after answering
class _ExplanationCard extends StatelessWidget {
  final String explanation;
  final bool isCorrect;

  const _ExplanationCard({
    required this.explanation,
    required this.isCorrect,
  });

  @override
  Widget build(BuildContext context) => AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isCorrect
              ? _kCorrect.withValues(alpha: 0.08)
              : _kError.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isCorrect
                ? _kCorrect.withValues(alpha: 0.4)
                : _kError.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              isCorrect ? Icons.check_circle : Icons.info_outline,
              color: isCorrect ? _kCorrect : _kError,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                explanation,
                style: TextStyle(
                  fontSize: 14,
                  color: isCorrect ? _kCorrect : _kError,
                  fontWeight: FontWeight.w500,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );
}

/// Circular blue button that plays TTS audio
class _CircleAudioBtn extends StatelessWidget {
  final String text;
  final double size;
  const _CircleAudioBtn({required this.text, this.size = 56});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(color: _kPrimary, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: SpeakIconButton(text: text, size: size * 0.45, color: Colors.white),
      );
}

/// Extract first quoted word from text — tries single then double quotes
String _extractQuotedWord(String text) {
  final s = RegExp("'([^']+)'").firstMatch(text);
  if (s != null) return s.group(1)!;
  final d = RegExp('"([^"]+)"').firstMatch(text);
  if (d != null) return d.group(1)!;
  return '';
}

String formatFillBlankPrompt(String question, String correctAnswer) {
  if (!question.contains('{blank}')) return question;
  final words = correctAnswer.split(' ');
  final blankRep = words.map((w) => '_' * w.length).join(' ');
  return question.replaceAll('{blank}', blankRep);
}

// ═══════════════════════════════════════════════════════════════
// 1. True or False
// ═══════════════════════════════════════════════════════════════
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
    final options = ['True', 'False'];
    final letters = ['A', 'B'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Badge('TRUE OR FALSE'),
          const SizedBox(height: 20),
          // Question card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Text(
              exercise.question,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: _kTextDark,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 28),
          ...List.generate(options.length, (i) {
            final opt = options[i];
            final sel = userAnswer == opt;
            final correct = exercise.correctAnswer.toLowerCase() == opt.toLowerCase();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                label: letters[i],
                isSelected: sel,
                isCorrect: correct,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
                radius: 20,
              ),
            );
          }),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 2. Multiple Choice
// ═══════════════════════════════════════════════════════════════
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
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Badge('MULTIPLE CHOICE'),
          const SizedBox(height: 20),
          // Question
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  exercise.question,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: _kTextDark,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SpeakIconButton(text: exercise.question, size: 22, color: _kPrimary),
            ],
          ),
          const SizedBox(height: 24),
          ...options.map((opt) {
            final sel  = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                showRadio: true,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
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

  // Build sentence with a highlighted slot for the blank
  Widget _buildSentence(String? selected) {
    final q = widget.exercise.question;
    if (!q.contains('{blank}')) {
      return Text(q,
          style: const TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: _kTextDark, height: 1.4));
    }
    final parts = q.split('{blank}');
    final before = parts[0];
    final after  = parts.length > 1 ? parts[1] : '';
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(before,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kTextDark, height: 1.4)),
        if (selected != null)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: _kPrimary,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(selected,
                style: const TextStyle(
                    fontSize: 20, fontWeight: FontWeight.w700, color: Colors.white)),
          )
        else
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 72,
            height: 28,
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: _kPrimary, width: 2.5)),
            ),
          ),
        Text(after,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kTextDark, height: 1.4)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final options = widget.exercise.options;
    final hasOptions = options != null && options.isNotEmpty;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'FILL IN THE BLANK',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: _kPrimary, letterSpacing: 1.2),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chọn từ phù hợp nhất để hoàn thành câu.',
            style: TextStyle(fontSize: 13, color: _kTextMid),
          ),
          const SizedBox(height: 20),
          // Sentence card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: _buildSentence(widget.userAnswer),
          ),
          const SizedBox(height: 24),
          if (hasOptions) ...[
            ...List.generate(options.length, (i) {
              final opt  = options[i];
              final sel  = widget.userAnswer == opt;
              final corr = widget.exercise.correctAnswer == opt;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
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
                hintText: 'Nhập câu trả lời...',
                filled: true,
                fillColor: _kCard,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kBorder, width: 1.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kPrimary, width: 2),
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
                  if (_ctrl.text.trim().isNotEmpty) widget.onAnswer(_ctrl.text.trim());
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(999)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                ),
                child: const Text('Xác nhận',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
          ],
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 4. Arrange the Sentence
// ═══════════════════════════════════════════════════════════════
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
  final List<String> _placed  = [];
  late List<String> _bank;

  @override
  void initState() {
    super.initState();
    _bank = List<String>.from(widget.exercise.options ?? []);
  }

  void _placeWord(String word) {
    setState(() {
      _bank.remove(word);
      _placed.add(word);
    });
    widget.onAnswer(_placed.join(' '));
  }

  void _removeWord(String word) {
    if (widget.isAnswered) return;
    setState(() {
      _placed.remove(word);
      _bank.add(word);
    });
    widget.onAnswer(_placed.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Sắp xếp câu',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          const SizedBox(height: 6),
          Text(
            exerciseQuote(widget.exercise.question),
            style: const TextStyle(fontSize: 14, color: _kTextMid, height: 1.4),
          ),
          const SizedBox(height: 24),
          // Drop zone (placed words)
          Container(
            constraints: const BoxConstraints(minHeight: 80),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _kBorder,
                style: BorderStyle.solid,
                width: 1.5,
              ),
            ),
            child: _placed.isEmpty
                ? const Center(
                    child: Text(
                      'Nhấn vào từ bên dưới để sắp xếp...',
                      style: TextStyle(fontSize: 13, color: _kTextLight),
                    ),
                  )
                : Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _placed
                        .map(
                          (w) => GestureDetector(
                            onTap: () => _removeWord(w),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 8),
                              decoration: BoxDecoration(
                                color: _kPrimary,
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(color: _kPrimaryDk),
                              ),
                              child: Text(
                                w,
                                style: const TextStyle(
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
                            horizontal: 16, vertical: 10),
                        decoration: BoxDecoration(
                          color: _kCard,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(color: _kBorder, width: 1.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 5,
                              offset: const Offset(0, 2),
                            )
                          ],
                        ),
                        child: Text(
                          w,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: _kTextDark,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 20),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
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

// ═══════════════════════════════════════════════════════════════
// 5. Translation Choice
// ═══════════════════════════════════════════════════════════════
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
    final options = exercise.options ?? [];

    // Extract source sentence (strip instruction prefix)
    String source = exercise.question;
    for (final prefix in [
      'Translate to English:',
      'Choose the translation for:',
      'Choose the correct translation:',
      'Translation of:',
    ]) {
      if (source.contains(prefix)) {
        source = source.substring(source.indexOf(prefix) + prefix.length).trim();
        break;
      }
    }
    // Remove surrounding quotes
    // Strip surrounding quotes
    if ((source.startsWith("'") && source.endsWith("'")) ||
        (source.startsWith('"') && source.endsWith('"'))) {
      source = source.substring(1, source.length - 1).trim();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Chọn bản dịch đúng',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          const SizedBox(height: 20),
          // Source sentence card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.volume_up_rounded,
                      color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    '"$source"',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: _kTextDark,
                      height: 1.4,
                    ),
                  ),
                ),
                SpeakIconButton(
                  text: source,
                  size: 18,
                  color: _kPrimary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          ...List.generate(options.length, (i) {
            final opt  = options[i];
            final sel  = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                label: '${i + 1}',
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

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
    final (lineA, lineB) = _parseDialogue();
    final options = widget.exercise.options ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Hoàn thành đoạn hội thoại',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          const SizedBox(height: 24),
          // Person A bubble (left)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const CircleAvatar(
                radius: 18,
                backgroundColor: _kSurface,
                child:
                    Icon(Icons.person_outline, size: 20, color: _kTextMid),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kCard,
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(20),
                      topRight: Radius.circular(20),
                      bottomRight: Radius.circular(20),
                    ),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Text(
                    '"$lineA"',
                    style: const TextStyle(
                        fontSize: 15, color: _kTextDark, height: 1.4),
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
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: _kSurface,
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
                          style: const TextStyle(
                            fontSize: 15,
                            color: _kPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              const CircleAvatar(
                radius: 18,
                backgroundColor: _kPrimary,
                child: Icon(Icons.person, size: 20, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 28),
          ...options.map((opt) {
            final sel  = widget.userAnswer == opt;
            final corr = widget.exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: widget.isAnswered,
                onTap: () => widget.onAnswer(opt),
                radius: 16,
              ),
            );
          }),
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBlankedLine(String line) {
    final parts = line.split('{blank}');
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(parts[0],
            style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: _kTextDark)),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          width: 84,
          height: 36,
          decoration: BoxDecoration(
            color: widget.isAnswered ? _kPrimary : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: _kPrimary,
              width: 1.5,
            ),
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
              color: widget.isAnswered ? Colors.white : _kTextDark,
            ),
            decoration: const InputDecoration(
              hintText: '____',
              hintStyle: TextStyle(
                color: _kPrimary,
                fontWeight: FontWeight.w700,
              ),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 8,
              ),
            ),
          ),
        ),
        if (parts.length > 1)
          Text(parts[1],
              style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: _kTextDark)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 7. Collocation Choice
// ═══════════════════════════════════════════════════════════════
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

  String _extractMainWord() => _extractQuotedWord(exercise.question);

  @override
  Widget build(BuildContext context) {
    final options = exercise.options ?? [];
    final mainWord = _extractMainWord();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            mainWord.isNotEmpty
                ? 'Chọn cụm từ đi với "$mainWord"'
                : exercise.question,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _kTextDark, height: 1.3),
          ),
          const SizedBox(height: 6),
          const Text(
            'Tìm từ kết hợp chính xác để hoàn thành ý nghĩa.',
            style: TextStyle(fontSize: 13, color: _kTextMid),
          ),
          const SizedBox(height: 20),
          if (mainWord.isNotEmpty) ...[
            // Main verb / key word card
            Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: _kPrimary.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  const Text(
                    'ĐỘNG TỪ CHÍNH',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kPrimary,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    mainWord,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w800,
                      color: _kPrimary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
          ],
          ...options.map((opt) {
            final sel  = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                showRadio: true,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (exercise.hint != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lightbulb_outline,
                      size: 18, color: _kPrimary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Mẹo: ${exercise.hint!}',
                      style: const TextStyle(
                          fontSize: 13, color: _kTextMid, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 8. Dictation
// ═══════════════════════════════════════════════════════════════
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
  final TextEditingController _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  int get _wordCount => widget.exercise.correctAnswer.trim().split(' ').length;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Dictation',
            style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: _kPrimary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          const Text(
            'Lắng nghe và điền vào chỗ trống',
            style: TextStyle(fontSize: 14, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Audio button
          Center(
            child: _CircleAudioBtn(
              text: widget.exercise.correctAnswer,
              size: 60,
            ),
          ),
          const SizedBox(height: 28),
          // Input field
          TextField(
            controller: _ctrl,
            enabled: !widget.isAnswered,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Nhập nội dung bạn nghe được...',
              hintStyle: const TextStyle(color: _kTextLight),
              filled: true,
              fillColor: _kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kBorder, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kPrimary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: BoxDecoration(
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$_wordCount từ cần điền',
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _kTextMid),
                ),
              ),
            ],
          ),
          if (!widget.isAnswered) ...[
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty)
                  widget.onAnswer(_ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Xác nhận',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 9. Grammar Correction
// ═══════════════════════════════════════════════════════════════
class GrammarCorrectionWidget extends StatelessWidget {
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

  String _extractError() {
    final quoted = _extractQuotedWord(exercise.question);
    if (quoted.isNotEmpty) return quoted;
    final colonIdx = exercise.question.indexOf(':');
    if (colonIdx != -1) {
      return exercise.question.substring(colonIdx + 1).trim();
    }
    return exercise.question;
  }

  @override
  Widget build(BuildContext context) {
    final options = exercise.options ?? [];
    final errorSentence = _extractError();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Chọn câu đúng',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          const SizedBox(height: 4),
          const Text(
            'Chọn phiên bản chính xác của câu dưới đây:',
            style: TextStyle(fontSize: 13, color: _kTextMid),
          ),
          const SizedBox(height: 20),
          // Error sentence card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kError.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(16),
              border:
                  Border.all(color: _kError.withValues(alpha: 0.3), width: 1.5),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _kPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.info_outline,
                      color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'CÂU SAI',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _kPrimary,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '"$errorSentence"',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _kTextDark,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          if (options.isNotEmpty) ...[
            ...List.generate(options.length, (i) {
              final opt  = options[i];
              final sel  = userAnswer == opt;
              final corr = exercise.correctAnswer == opt;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _OptionCard(
                  text: opt,
                  label: '${i + 1}',
                  isSelected: sel,
                  isCorrect: corr,
                  isAnswered: isAnswered,
                  onTap: () => onAnswer(opt),
                ),
              );
            }),
          ] else ...[
            _GrammarTextInput(
              exercise: exercise,
              onAnswer: onAnswer,
              isAnswered: isAnswered,
            ),
          ],
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

class _GrammarTextInput extends StatefulWidget {
  final Exercise exercise;
  final Function(String) onAnswer;
  final bool isAnswered;
  const _GrammarTextInput(
      {required this.exercise, required this.onAnswer, required this.isAnswered});

  @override
  State<_GrammarTextInput> createState() => _GrammarTextInputState();
}

class _GrammarTextInputState extends State<_GrammarTextInput> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          TextField(
            controller: _ctrl,
            enabled: !widget.isAnswered,
            decoration: InputDecoration(
              hintText: 'Viết câu đúng...',
              filled: true,
              fillColor: _kCard,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: const BorderSide(color: _kPrimary, width: 2)),
            ),
          ),
          if (!widget.isAnswered) ...[
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty)
                  widget.onAnswer(_ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                padding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 32),
              ),
              child: const Text('Xác nhận',
                  style:
                      TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ],
        ],
      );
}

// ═══════════════════════════════════════════════════════════════
// 10. Image Based Choice
// ═══════════════════════════════════════════════════════════════
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
    final imageUrl = exercise.metadata?['image_url'] as String?;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Badge('IMAGE CHOICE'),
          const SizedBox(height: 16),
          Text(
            exercise.question,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kTextDark),
          ),
          const SizedBox(height: 16),
          // Image area
          ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: imageUrl != null
                ? Image.network(imageUrl,
                    height: 200, fit: BoxFit.cover)
                : Container(
                    height: 180,
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(Icons.image_outlined,
                        size: 64, color: _kBorder),
                  ),
          ),
          const SizedBox(height: 20),
          // 2x2 grid options
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.5,
            children: options.map((opt) {
              final sel  = userAnswer == opt;
              final corr = exercise.correctAnswer == opt;
              return _OptionCard(
                text: opt,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
                radius: 999,
              );
            }).toList(),
          ),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 11. Listen and Choose
// ═══════════════════════════════════════════════════════════════
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
    final options = exercise.options ?? [];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _Badge('LISTENING', icon: Icons.volume_up_rounded),
          const SizedBox(height: 16),
          Text(
            exercise.question,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: _kTextDark, height: 1.3),
          ),
          const SizedBox(height: 20),
          // Tap-to-listen card
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder, width: 1.5),
            ),
            child: Column(
              children: [
                _CircleAudioBtn(text: exercise.correctAnswer, size: 56),
                const SizedBox(height: 14),
                const Text(
                  'TAP TO LISTEN',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kTextMid,
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          ...List.generate(options.length, (i) {
            final opt  = options[i];
            final sel  = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                label: '${i + 1}',
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 12. Match Word to Meaning
// ═══════════════════════════════════════════════════════════════
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
  final Map<String, String> _matched = {};

  @override
  Widget build(BuildContext context) {
    final options = widget.exercise.options ?? [];
    final half    = options.length ~/ 2;
    final left    = options.take(half).toList();
    final right   = options.skip(half).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Nối cặp từ tương ứng',
            style: TextStyle(
                fontSize: 20, fontWeight: FontWeight.w800, color: _kTextDark),
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
                      final isSelected    = _selectedLeft == item;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: GestureDetector(
                          onTap: widget.isAnswered || isMatchedLeft
                              ? null
                              : () {
                                  setState(() {
                                    _selectedLeft =
                                        isSelected ? null : item;
                                  });
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color: isMatchedLeft
                                  ? _kCorrect
                                  : isSelected
                                      ? _kPrimary
                                      : _kCard,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isMatchedLeft
                                    ? _kCorrect
                                    : isSelected
                                        ? _kPrimary
                                        : _kBorder,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
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
                                    : _kTextDark,
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
                                    final ans = _matched.entries
                                        .map((e) => '${e.key}:${e.value}')
                                        .join(', ');
                                    widget.onAnswer(ans);
                                  }
                                },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 14),
                            decoration: BoxDecoration(
                              color:
                                  isMatchedRight ? _kCorrect : _kCard,
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(
                                color: isMatchedRight ? _kCorrect : _kBorder,
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color:
                                      Colors.black.withValues(alpha: 0.05),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                )
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
                                    : _kTextDark,
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
              color: _kSurface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Row(
              children: [
                Icon(Icons.lightbulb_outline, size: 16, color: _kPrimary),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Chọn một từ tiếng Anh và nghĩa tiếng Việt tương ứng để nối chúng.',
                    style: TextStyle(fontSize: 12, color: _kTextMid, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 12),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 13. Vocabulary Flashcard
// ═══════════════════════════════════════════════════════════════
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
  State<VocabularyFlashcardWidget> createState() =>
      _VocabularyFlashcardWidgetState();
}

class _VocabularyFlashcardWidgetState
    extends State<VocabularyFlashcardWidget> {
  // Extract the word from question (e.g. "Learn: 'Adventure'" → "Adventure")
  String get _word {
    final quoted = _extractQuotedWord(widget.exercise.question);
    if (quoted.isNotEmpty) return quoted;
    final colonIdx = widget.exercise.question.indexOf(':');
    if (colonIdx != -1) return widget.exercise.question.substring(colonIdx + 1).trim();
    return widget.exercise.question;
  }

  @override
  Widget build(BuildContext context) {
    final options  = widget.exercise.options ?? [];
    final imageUrl = widget.exercise.metadata?['image_url'] as String?;
    final word     = _word;

    // If options is just ["Got it!"], show simple flashcard
    if (options.length == 1 && options[0] == 'Got it!') {
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          children: [
            // Flashcard
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: _kBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: 0.07),
                      blurRadius: 20,
                      offset: const Offset(0, 6))
                ],
              ),
              child: Column(
                children: [
                  _CircleAudioBtn(text: word, size: 36),
                  const SizedBox(height: 12),
                  Text(
                    word,
                    style: const TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w800,
                        color: _kPrimary),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.exercise.explanation != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      widget.exercise.explanation!,
                      style: const TextStyle(
                          fontSize: 13, color: _kTextMid, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (imageUrl != null) ...[
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(imageUrl,
                          height: 140, fit: BoxFit.cover),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 24),
            GestureDetector(
              onTap: widget.isAnswered
                  ? null
                  : () => widget.onAnswer('Got it!'),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(
                    horizontal: 40, vertical: 16),
                decoration: BoxDecoration(
                  color: widget.isAnswered ? _kCorrect : _kPrimary,
                  borderRadius: BorderRadius.circular(999),
                  boxShadow: [
                    BoxShadow(
                        color: _kPrimary.withValues(alpha: 0.3),
                        blurRadius: 12,
                        offset: const Offset(0, 4))
                  ],
                ),
                child: const Text(
                  'Đã hiểu rồi!',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // Vocab MCQ variant: word + "What is the meaning?" + options
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Flashcard header
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [_CircleAudioBtn(text: word, size: 36)],
                ),
                const SizedBox(height: 10),
                Text(
                  word,
                  style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: _kPrimary),
                  textAlign: TextAlign.center,
                ),
                if (imageUrl != null) ...[
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.network(imageUrl,
                        height: 120, fit: BoxFit.cover,
                        width: double.infinity),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'What is the meaning?',
            style: TextStyle(
                fontSize: 17, fontWeight: FontWeight.w700, color: _kTextDark),
          ),
          const SizedBox(height: 12),
          ...List.generate(options.length, (i) {
            final opt  = options[i];
            final sel  = widget.userAnswer == opt;
            final corr = widget.exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _OptionCard(
                text: opt,
                label: '${i + 1}',
                labelOnRight: true,
                isSelected: sel,
                isCorrect: corr,
                isAnswered: widget.isAnswered,
                onTap: () => widget.onAnswer(opt),
              ),
            );
          }),
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 14. Pronunciation Practice
// ═══════════════════════════════════════════════════════════════
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
  State<PronunciationPracticeWidget> createState() =>
      _PronunciationPracticeWidgetState();
}

class _PronunciationPracticeWidgetState
    extends State<PronunciationPracticeWidget> {
  bool _hasTapped = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Luyện phát âm',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: _kTextDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Nghe và lặp lại câu dưới đây',
            style: TextStyle(fontSize: 13, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Sentence card with speaker
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Row(
              children: [
                _CircleAudioBtn(text: widget.exercise.question, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '"${widget.exercise.question}"',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: _kTextDark,
                          height: 1.4,
                        ),
                      ),
                      if (widget.exercise.explanation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          widget.exercise.explanation!,
                          style: const TextStyle(
                              fontSize: 12, color: _kTextMid, fontStyle: FontStyle.italic),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Microphone button
          Center(
            child: GestureDetector(
              onTap: widget.isAnswered
                  ? null
                  : () {
                      setState(() => _hasTapped = true);
                      widget.onAnswer(widget.exercise.correctAnswer);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasTapped || widget.isAnswered
                      ? _kPrimary
                      : Colors.transparent,
                  border: Border.all(color: _kPrimary, width: 2.5),
                  boxShadow: (_hasTapped || widget.isAnswered)
                      ? [
                          BoxShadow(
                            color: _kPrimary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          )
                        ]
                      : [],
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 36,
                  color: (_hasTapped || widget.isAnswered)
                      ? Colors.white
                      : _kPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Nhấn để nói',
            style: const TextStyle(fontSize: 13, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 15. Reading Comprehension
// ═══════════════════════════════════════════════════════════════
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

  // The question contains the passage + "?" question
  // Try to split on the last sentence that ends with "?"
  (String, String) _splitPassageAndQuestion() {
    final q = exercise.question;
    // Find last sentence that looks like a question
    final sentences = q.split(RegExp(r'(?<=[.!?])\s+'));
    if (sentences.length > 1) {
      final last = sentences.last;
      if (last.trim().endsWith('?')) {
        final passage = sentences.sublist(0, sentences.length - 1).join(' ');
        return (passage.trim(), last.trim());
      }
    }
    // Fallback: whole question is the question, no passage
    return ('', q);
  }

  @override
  Widget build(BuildContext context) {
    final (passage, question) = _splitPassageAndQuestion();
    final options = exercise.options ?? [];
    final letters = ['A', 'B', 'C', 'D', 'E'];

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Đọc hiểu',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark),
          ),
          const SizedBox(height: 4),
          const Text(
            'Đọc đoạn văn sau và trả lời câu hỏi bên dưới.',
            style: TextStyle(fontSize: 13, color: _kTextMid),
          ),
          if (passage.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(maxHeight: 160),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _kBorder),
              ),
              child: SingleChildScrollView(
                child: Text(
                  passage,
                  style: const TextStyle(
                      fontSize: 14, color: _kTextDark, height: 1.6),
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            question,
            style: const TextStyle(
                fontSize: 18, fontWeight: FontWeight.w700, color: _kTextDark, height: 1.3),
          ),
          const SizedBox(height: 16),
          ...List.generate(options.length, (i) {
            final opt  = options[i];
            final sel  = userAnswer == opt;
            final corr = exercise.correctAnswer == opt;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _OptionCard(
                text: opt,
                label: i < letters.length ? letters[i] : '${i + 1}',
                isSelected: sel,
                isCorrect: corr,
                isAnswered: isAnswered,
                onTap: () => onAnswer(opt),
              ),
            );
          }),
          if (isAnswered && exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: exercise.explanation!,
              isCorrect: isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

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

  String _extractHighlightWord() => _extractQuotedWord(widget.exercise.question);

  @override
  Widget build(BuildContext context) {
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
                  color: _kSurface,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.edit_note_rounded,
                    size: 20, color: _kPrimary),
              ),
              const SizedBox(width: 10),
              const Text(
                'VIẾT CÂU NGẮN',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                    letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Question with highlighted word
          RichText(
            text: TextSpan(
              style: const TextStyle(
                  fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark, height: 1.3),
              children: [
                TextSpan(
                    text: widget.exercise.question
                        .replaceAll('"$highlight"', '')
                        .replaceAll("'$highlight'", '')
                        .trimRight()
                        .replaceAll(RegExp(r'\s+$'), '')
                ),
                if (highlight.isNotEmpty) ...[
                  const TextSpan(text: ' '),
                  TextSpan(
                    text: '"$highlight"',
                    style: const TextStyle(color: _kPrimary),
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
              hintText: 'Nhập câu trả lời của bạn tại đây...',
              hintStyle: const TextStyle(color: _kTextLight, fontSize: 14),
              filled: true,
              fillColor: _kCard,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kBorder, width: 1.5),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: const BorderSide(color: _kPrimary, width: 2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (!widget.isAnswered)
            ElevatedButton(
              onPressed: () {
                if (_ctrl.text.trim().isNotEmpty)
                  widget.onAnswer(_ctrl.text.trim());
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999)),
                padding: const EdgeInsets.symmetric(vertical: 15),
              ),
              child: const Text('Kiểm tra',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 17. Speaking Repeat
// ═══════════════════════════════════════════════════════════════
class SpeakingRepeatWidget extends StatefulWidget {
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
  State<SpeakingRepeatWidget> createState() => _SpeakingRepeatWidgetState();
}

class _SpeakingRepeatWidgetState extends State<SpeakingRepeatWidget> {
  bool _hasTapped = false;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'LUYỆN NÓI',
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _kPrimary,
                letterSpacing: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          const Text(
            'Lặp lại câu sau',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: _kTextDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // Sentence card with speaker + translation
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _kCard,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              children: [
                _CircleAudioBtn(text: widget.exercise.question, size: 40),
                const SizedBox(height: 14),
                Text(
                  '"${widget.exercise.question}"',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: _kPrimary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.exercise.explanation != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    widget.exercise.explanation!,
                    style: const TextStyle(
                        fontSize: 13,
                        color: _kTextMid,
                        fontStyle: FontStyle.italic,
                        height: 1.4),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
          const Spacer(),
          // Microphone
          Center(
            child: GestureDetector(
              onTap: widget.isAnswered
                  ? null
                  : () {
                      setState(() => _hasTapped = true);
                      widget.onAnswer(widget.exercise.correctAnswer);
                    },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _hasTapped || widget.isAnswered
                      ? _kPrimary
                      : Colors.transparent,
                  border: Border.all(color: _kPrimary, width: 2.5),
                  boxShadow: (_hasTapped || widget.isAnswered)
                      ? [
                          BoxShadow(
                            color: _kPrimary.withValues(alpha: 0.3),
                            blurRadius: 20,
                            spreadRadius: 4,
                          )
                        ]
                      : [],
                ),
                child: Icon(
                  Icons.mic_rounded,
                  size: 36,
                  color: (_hasTapped || widget.isAnswered)
                      ? Colors.white
                      : _kPrimary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          const Text(
            'Nhấn để bắt đầu nói',
            style: TextStyle(fontSize: 13, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 18. Categorization (Phân loại từ vựng)
// ═══════════════════════════════════════════════════════════════
class CategorizationWidget extends StatefulWidget {
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
  State<CategorizationWidget> createState() => _CategorizationWidgetState();
}

class _CategorizationWidgetState extends State<CategorizationWidget> {
  String? _selectedWord;
  final Map<String, String> _assignments = {}; // word → category

  @override
  Widget build(BuildContext context) {
    final options = widget.exercise.options ?? [];
    final half    = options.length ~/ 2;
    final words   = options.take(half).toList();
    final cats    = options.skip(half).toList();

    final unassigned = words.where((w) => !_assignments.containsKey(w)).toList();

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Phân loại từ vựng',
            style: TextStyle(
                fontSize: 22, fontWeight: FontWeight.w800, color: _kTextDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          const Text(
            'Nhấn một từ rồi nhấn vào danh mục phù hợp.',
            style: TextStyle(fontSize: 13, color: _kTextMid),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          // Category buckets
          ...List.generate(cats.length, (ci) {
            final cat      = cats[ci];
            final assigned = _assignments.entries
                .where((e) => e.value == cat)
                .map((e) => e.key)
                .toList();
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: GestureDetector(
                onTap: widget.isAnswered || _selectedWord == null
                    ? null
                    : () {
                        setState(() {
                          _assignments[_selectedWord!] = cat;
                          _selectedWord = null;
                        });
                        final ans = _assignments.entries
                            .map((e) => '${e.key}:${e.value}')
                            .join(', ');
                        widget.onAnswer(ans);
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(14),
                  constraints: const BoxConstraints(minHeight: 72),
                  decoration: BoxDecoration(
                    color: _selectedWord != null && !widget.isAnswered
                        ? _kPrimary.withValues(alpha: 0.06)
                        : _kCard,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: _selectedWord != null && !widget.isAnswered
                          ? _kPrimary
                          : _kBorder,
                      width: 1.5,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            ci == 0 ? Icons.category_outlined : Icons.bolt_outlined,
                            size: 18,
                            color: ci == 0 ? _kPrimary : const Color(0xFF00A86B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            cat.toUpperCase(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: ci == 0 ? _kPrimary : const Color(0xFF00A86B),
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
                          children: assigned
                              .map(
                                (w) => GestureDetector(
                                  onTap: widget.isAnswered
                                      ? null
                                      : () {
                                          setState(() =>
                                              _assignments.remove(w));
                                        },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 7),
                                    decoration: BoxDecoration(
                                      color: _kSurface,
                                      borderRadius:
                                          BorderRadius.circular(999),
                                    ),
                                    child: Text(
                                      w,
                                      style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: _kPrimary),
                                    ),
                                  ),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 8),
          // Word bank (unassigned)
          if (unassigned.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _kSurface,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: unassigned.map((w) {
                  final sel = _selectedWord == w;
                  return GestureDetector(
                    onTap: widget.isAnswered
                        ? null
                        : () => setState(
                            () => _selectedWord = sel ? null : w),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 9),
                      decoration: BoxDecoration(
                        color: sel ? _kPrimary : _kCard,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: sel ? _kPrimary : _kBorder, width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          )
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.drag_indicator,
                              size: 14,
                              color: sel ? Colors.white : _kTextLight),
                          const SizedBox(width: 4),
                          Text(
                            w,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: sel ? Colors.white : _kTextDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
          if (widget.isAnswered && widget.exercise.explanation != null) ...[
            const SizedBox(height: 16),
            _ExplanationCard(
              explanation: widget.exercise.explanation!,
              isCorrect: widget.isCorrect ?? false,
            ),
          ],
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// 19. Cognitive Fluidity (fast matching — same layout as Match)
// ═══════════════════════════════════════════════════════════════
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
  Widget build(BuildContext context) => MatchWordMeaningWidget(
        exercise: exercise,
        onAnswer: onAnswer,
        isAnswered: isAnswered,
        userAnswer: userAnswer,
        isCorrect: isCorrect,
      );
}
