import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:lexilingo_app/features/level/presentation/level_sync.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_exam_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/test_answer_option.dart';
import 'package:provider/provider.dart';

/// The CEFR promotion exam. Pops `true` when the certified level went up.
class LevelExamPage extends StatefulWidget {
  const LevelExamPage({super.key});

  @override
  State<LevelExamPage> createState() => _LevelExamPageState();
}

class _LevelExamPageState extends State<LevelExamPage> {
  Timer? _clock;
  bool _promoted = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<LevelExamProvider>().loadEligibility();
    });
    // Repaints the time left; the deadline itself is the server's.
    _clock = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && context.read<LevelExamProvider>().sitting) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  Future<void> _submit(LevelExamProvider exam) async {
    final promoted = await exam.submit();
    if (promoted && mounted) {
      _promoted = true;
      await LevelSync.afterLevelChange(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exam = context.watch<LevelExamProvider>();
    final Widget body;
    if (exam.result != null) {
      body = _Result(
        result: exam.result!,
        onDone: () => Navigator.of(context).pop(_promoted),
      );
    } else if (exam.sitting) {
      body = _Sitting(exam: exam, onSubmit: () => _submit(exam));
    } else if (exam.loading && exam.gate.isEmpty) {
      body = const Center(child: CircularProgressIndicator());
    } else if (exam.blockedReason != null) {
      body = _Gate(reason: exam.blockedReason!, gate: exam.gate);
    } else {
      body = _Intro(exam: exam);
    }
    return PopScope(
      canPop: !exam.sitting,
      child: Scaffold(
        appBar: AppBar(title: Text('levelExam.title'.tr())),
        body: SafeArea(
          child: ContentWidth(
            child: Padding(padding: const EdgeInsets.all(16), child: body),
          ),
        ),
      ),
    );
  }
}

String _localTime(Object? iso) {
  final at = DateTime.tryParse('$iso')?.toLocal();
  return at == null ? '' : DateFormat.yMMMd().add_Hm().format(at);
}

class _Gate extends StatelessWidget {
  const _Gate({required this.reason, required this.gate});

  final String reason;
  final Map<String, dynamic> gate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final blockers = (gate['blockers'] as List? ?? const []).cast<Object>();
    final message = switch (reason) {
      'not_ready' => 'levelExam.gateNotReady'.tr(
        namedArgs: {
          'level': '${gate['target_level'] ?? ''}',
          'progress': '${((gate['progress'] as num?) ?? 0).round()}',
        },
      ),
      'cooldown' => 'levelExam.gateCooldown'.tr(
        namedArgs: {'time': _localTime(gate['retry_at'])},
      ),
      'expired' => 'levelExam.gateExpired'.tr(
        namedArgs: {'time': _localTime(gate['retry_at'])},
      ),
      'no_questions' => 'levelExam.gateNoQuestions'.tr(),
      'max_level' => 'levelExam.gateMaxLevel'.tr(),
      _ => 'levelExam.gateError'.tr(),
    };
    return ListView(
      children: [
        Icon(
          reason == 'max_level'
              ? Icons.emoji_events_rounded
              : Icons.lock_clock_rounded,
          size: 48,
          color: theme.colorScheme.primary,
        ),
        const SizedBox(height: 16),
        Text(
          message,
          style: theme.textTheme.titleMedium,
          textAlign: TextAlign.center,
        ),
        if (reason == 'not_ready' && blockers.isNotEmpty) ...[
          const SizedBox(height: 16),
          for (final blocker in blockers)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.radio_button_unchecked,
                    size: 16,
                    color: theme.colorScheme.outline,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('$blocker', style: theme.textTheme.bodyMedium),
                  ),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro({required this.exam});

  final LevelExamProvider exam;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resuming = exam.gate['reason'] == 'in_progress';
    return ListView(
      children: [
        Text(
          'levelExam.introTitle'.tr(
            namedArgs: {'level': '${exam.gate['target_level'] ?? ''}'},
          ),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Text('levelExam.introBody'.tr(), style: theme.textTheme.bodyMedium),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: exam.loading ? null : exam.start,
          child: Text((resuming ? 'levelExam.resume' : 'levelExam.start').tr()),
        ),
      ],
    );
  }
}

class _Sitting extends StatelessWidget {
  const _Sitting({required this.exam, required this.onSubmit});

  final LevelExamProvider exam;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final question = exam.current!;
    final last = exam.index == exam.questions.length - 1;
    final left = exam.expiresAt?.difference(DateTime.now());
    final timeLeft = left == null || left.isNegative
        ? '0:00'
        : '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Chip(
              label: Text(
                'levelExam.sectionLevel'.tr(
                  namedArgs: {'level': question.level},
                ),
              ),
            ),
            const Spacer(),
            Text(
              'levelExam.questionOf'.tr(
                namedArgs: {
                  'current': '${exam.index + 1}',
                  'total': '${exam.questions.length}',
                },
              ),
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(width: 12),
            Text(
              'levelExam.timeLeft'.tr(namedArgs: {'time': timeLeft}),
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (exam.index + 1) / exam.questions.length,
        ),
        const SizedBox(height: 16),
        Expanded(
          child: ListView(
            children: [
              Text(question.prompt, style: theme.textTheme.titleMedium),
              const SizedBox(height: 16),
              for (final (i, option) in question.options.indexed)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TestAnswerOption(
                    index: i,
                    text: option,
                    selected: exam.answers[question.id] == option,
                    onTap: () => exam.answer(option),
                  ),
                ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: exam.index == 0
                    ? null
                    : () => exam.goTo(exam.index - 1),
                child: Text('levelExam.previous'.tr()),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: exam.loading
                    ? null
                    : last
                    ? (exam.allAnswered ? onSubmit : null)
                    : () => exam.goTo(exam.index + 1),
                child: Text(
                  (last ? 'levelExam.submit' : 'levelExam.next').tr(),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({required this.result, required this.onDone});

  final Map<String, dynamic> result;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final passed = result['passed'] == true;
    final sections = (result['sections'] as List? ?? const []).cast<Map>();
    return ListView(
      children: [
        Icon(
          passed ? Icons.verified_rounded : Icons.refresh_rounded,
          size: 56,
          color: passed ? theme.colorScheme.primary : theme.colorScheme.outline,
        ),
        const SizedBox(height: 12),
        Text(
          passed
              ? 'levelExam.passedTitle'.tr(
                  namedArgs: {'level': '${result['result_level']}'},
                )
              : 'levelExam.failedTitle'.tr(),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final section in sections)
          ListTile(
            leading: Icon(
              section['passed'] == true
                  ? Icons.check_circle_rounded
                  : Icons.cancel_rounded,
              color: section['passed'] == true
                  ? theme.colorScheme.primary
                  : theme.colorScheme.error,
            ),
            title: Text(
              'levelExam.sectionRow'.tr(
                namedArgs: {
                  'level': '${section['level']}',
                  'correct': '${section['correct']}',
                  'total': '${section['total']}',
                },
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          passed
              ? 'levelExam.certifiedNow'.tr(
                  namedArgs: {'level': '${result['certified_level']}'},
                )
              : 'levelExam.retryAt'.tr(
                  namedArgs: {'time': _localTime(result['retry_at'])},
                ),
          style: theme.textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
          onPressed: onDone,
          child: Text('levelExam.done'.tr()),
        ),
      ],
    );
  }
}
