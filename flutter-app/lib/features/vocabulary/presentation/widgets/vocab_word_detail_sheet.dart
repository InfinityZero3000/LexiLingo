import 'dart:math';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/voice/presentation/widgets/speak_button.dart';

/// Full flashcard bottom sheet for a [VocabWord].
/// Front: word + IPA + part of speech + tap hint.
/// Back : definition + example + audio speak button.
void showVocabWordDetail(BuildContext context, VocabWord word) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VocabWordDetailSheet(word: word),
  );
}

class _VocabWordDetailSheet extends StatefulWidget {
  final VocabWord word;
  const _VocabWordDetailSheet({required this.word});

  @override
  State<_VocabWordDetailSheet> createState() => _VocabWordDetailSheetState();
}

class _VocabWordDetailSheetState extends State<_VocabWordDetailSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;
  bool _showBack = false;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _anim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _flip() {
    if (_ctrl.isAnimating) return;
    if (_showBack) {
      _ctrl.reverse().then((_) => setState(() => _showBack = false));
    } else {
      _ctrl.forward().then((_) => setState(() => _showBack = true));
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cs = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Drag handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 12, bottom: 4),
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Header row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Flashcard',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: cs.onSurface,
                      ),
                    ),
                    Row(
                      children: [
                        _FlipHintChip(showBack: _showBack),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Flashcard
              Expanded(
                child: SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: _flip,
                        child: AnimatedBuilder(
                          animation: _anim,
                          builder: (context, _) {
                            final angle = _anim.value * pi;
                            final showingBack = angle > pi / 2;
                            return Transform(
                              alignment: Alignment.center,
                              transform: Matrix4.identity()
                                ..setEntry(3, 2, 0.001)
                                ..rotateY(angle),
                              child: showingBack
                                  ? Transform(
                                      alignment: Alignment.center,
                                      transform: Matrix4.identity()..rotateY(pi),
                                      child: _CardBack(
                                        word: widget.word,
                                        isDark: isDark,
                                      ),
                                    )
                                  : _CardFront(
                                      word: widget.word,
                                      isDark: isDark,
                                    ),
                            );
                          },
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Action buttons
                      Row(
                        children: [
                          Expanded(
                            child: _ActionButton(
                              icon: Icons.flip,
                              label: _showBack ? 'Show Front' : 'Flip Card',
                              onTap: _flip,
                              color: AppColors.primary,
                            ),
                          ),
                          if (widget.word.audioUrl != null &&
                              widget.word.audioUrl!.isNotEmpty) ...[
                            const SizedBox(width: 12),
                            Expanded(
                              child: SpeakButton(
                                text: widget.word.word,
                                size: 48,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ── Front face ──────────────────────────────────────────────────────────────

class _CardFront extends StatelessWidget {
  final VocabWord word;
  final bool isDark;
  const _CardFront({required this.word, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1E293B), const Color(0xFF0F172A)]
              : [Colors.white, const Color(0xFFF8FAFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : AppColors.primary.withValues(alpha: 0.12),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Part of speech badge
          if (word.partOfSpeech != null && word.partOfSpeech!.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                word.partOfSpeech!,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),

          const SizedBox(height: 24),

          // Word
          Text(
            word.word,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 44,
              fontWeight: FontWeight.bold,
              letterSpacing: -1,
              color: cs.onSurface,
            ),
          ),

          const SizedBox(height: 12),

          // IPA pronunciation
          if (word.pronunciation != null && word.pronunciation!.isNotEmpty)
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.record_voice_over_outlined,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Text(
                  word.pronunciation!,
                  style: TextStyle(
                    fontSize: 18,
                    color: cs.onSurfaceVariant,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),

          const SizedBox(height: 32),

          // Tap hint
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app_rounded,
                size: 18,
                color: cs.onSurfaceVariant.withValues(alpha: 0.5),
              ),
              const SizedBox(width: 6),
              Text(
                'vocabulary.tapToRevealDefinition'.tr(),
                style: TextStyle(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.6),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Back face ──────────────────────────────────────────────────────────────

class _CardBack extends StatelessWidget {
  final VocabWord word;
  final bool isDark;
  const _CardBack({required this.word, required this.isDark});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 260),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF1A2744), const Color(0xFF0F172A)]
              : [const Color(0xFFEEF4FF), Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.18),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(28),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Word mini header
          Row(
            children: [
              Text(
                word.word,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const Spacer(),
              SpeakIconButton(
                text: word.word,
                size: 22,
                color: AppColors.primary,
              ),
            ],
          ),

          const Divider(height: 24),

          // Definition
          _SectionLabel(label: 'vocabulary.definition'.tr()),
          const SizedBox(height: 8),
          Text(
            word.definition,
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: cs.onSurface,
            ),
          ),

          // Example
          if (word.example != null && word.example!.isNotEmpty) ...[
            const SizedBox(height: 20),
            _SectionLabel(label: 'Example'),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.15),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '"',
                    style: TextStyle(
                      fontSize: 28,
                      height: 0.9,
                      color: AppColors.primary.withValues(alpha: 0.5),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      word.example!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.5,
                        color: cs.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                  SpeakIconButton(
                    text: word.example!,
                    size: 18,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.2,
        color: AppColors.primary,
      ),
    );
  }
}

class _FlipHintChip extends StatelessWidget {
  final bool showBack;
  const _FlipHintChip({required this.showBack});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        showBack ? 'Back' : 'Front',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.primary,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
