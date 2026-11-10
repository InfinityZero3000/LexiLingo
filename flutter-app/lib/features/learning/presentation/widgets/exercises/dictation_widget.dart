import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_palette.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';

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
    final colors = ExercisePalette.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'lesson.exercise.dictationTitle'.tr(),
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w800,
              color: colors.primary,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'lesson.exercise.dictationInstruction'.tr(),
            style: TextStyle(fontSize: 14, color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 28),
          // Audio button
          Center(
            child: CircleAudioButton(
              text: widget.exercise.correctAnswer,
              audioUrl: widget.exercise.audioUrl,
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
              hintText: 'lesson.exercise.dictationHint'.tr(),
              hintStyle: TextStyle(color: colors.textMuted),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: colors.surface,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  'lesson.exercise.dictationWordCount'.tr(
                    namedArgs: {'count': '$_wordCount'},
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          if (!widget.isAnswered) ...[
            const SizedBox(height: 16),
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
