import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/features/level/presentation/providers/placement_test_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/test_answer_option.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class PlacementTestPage extends StatefulWidget {
  const PlacementTestPage({super.key});

  @override
  State<PlacementTestPage> createState() => _PlacementTestPageState();
}

class _PlacementTestPageState extends State<PlacementTestPage> {
  final Map<String, int> _answers = {};
  Timer? _timer;
  int _currentIndex = 0;
  int _elapsedSeconds = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadTest(reset: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _loadTest({bool reset = false}) async {
    if (reset) {
      _timer?.cancel();
      _answers.clear();
      _currentIndex = 0;
      _elapsedSeconds = 0;
      context.read<PlacementTestProvider>().reset();
      if (mounted) setState(() {});
    }

    await context.read<PlacementTestProvider>().loadTest();
    if (!mounted) return;

    if (context.read<PlacementTestProvider>().questions.isNotEmpty) {
      _startTimer();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _elapsedSeconds += 1);
    });
  }

  String _formatElapsedTime() {
    final minutes = (_elapsedSeconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_elapsedSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  void _selectAnswer(String questionId, int optionIndex) {
    setState(() {
      _answers[questionId] = optionIndex;
    });
  }

  void _goToQuestion(int index, int total) {
    if (index < 0 || index >= total) return;
    setState(() => _currentIndex = index);
  }

  Future<void> _submit() async {
    final provider = context.read<PlacementTestProvider>();
    final total = provider.questions.length;
    if (_answers.length < total) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('assessment.answerAllQuestions'.tr())),
      );
      return;
    }

    final submitted = await provider.submitTest(_answers, _elapsedSeconds);
    if (!mounted) return;

    if (submitted) {
      _timer?.cancel();
      await context.read<ProficiencyProvider>().loadProfile();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('assessment.placementTest'.tr()),
        actions: [
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 16),
            child: Center(
              child: _MetaChip(
                icon: Icons.timer_rounded,
                label: _formatElapsedTime(),
                color: accent,
              ),
            ),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: SafeArea(
          child: Consumer<PlacementTestProvider>(
            builder: (context, provider, _) {
              if (provider.isLoading && provider.questions.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (provider.errorMessage != null && provider.questions.isEmpty) {
                return _ErrorState(
                  message: provider.errorMessage!,
                  onRetry: () => _loadTest(reset: true),
                );
              }

              if (provider.result != null) {
                return _ResultState(
                  result: provider.result!,
                  onRetake: () => _loadTest(reset: true),
                );
              }

              if (provider.questions.isEmpty) {
                return _EmptyState(onRetry: () => _loadTest(reset: true));
              }

              return _QuestionState(
                questions: provider.questions,
                currentIndex: _currentIndex,
                answers: _answers,
                isSubmitting: provider.isLoading,
                elapsedLabel: _formatElapsedTime(),
                onSelectAnswer: _selectAnswer,
                onPrevious: () =>
                    _goToQuestion(_currentIndex - 1, provider.questions.length),
                onNext: () =>
                    _goToQuestion(_currentIndex + 1, provider.questions.length),
                onSubmit: _submit,
              );
            },
          ),
        ),
      ),
    );
  }
}

class _QuestionState extends StatelessWidget {
  const _QuestionState({
    required this.questions,
    required this.currentIndex,
    required this.answers,
    required this.isSubmitting,
    required this.elapsedLabel,
    required this.onSelectAnswer,
    required this.onPrevious,
    required this.onNext,
    required this.onSubmit,
  });

  final List<Map<String, dynamic>> questions;
  final int currentIndex;
  final Map<String, int> answers;
  final bool isSubmitting;
  final String elapsedLabel;
  final void Function(String questionId, int optionIndex) onSelectAnswer;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final question = questions[currentIndex];
    final questionId = '${question['id'] ?? currentIndex + 1}';
    final options = List<String>.from(question['options'] ?? const <String>[]);
    final selectedOption = answers[questionId];
    final isLast = currentIndex == questions.length - 1;
    final progress = (currentIndex + 1) / questions.length;
    final answeredCount = answers.length;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    final surface = Theme.of(context).colorScheme.surface;

    final border = isDark
        ? Theme.of(context).colorScheme.outlineVariant
        : Theme.of(context).colorScheme.outlineVariant;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'assessment.questionCounter'.tr(
                  namedArgs: {
                    'current': '${currentIndex + 1}',
                    'total': '${questions.length}',
                  },
                ),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _MetaChip(
              icon: Icons.fact_check_rounded,
              label: 'assessment.answeredCount'.tr(
                namedArgs: {
                  'answered': '$answeredCount',
                  'total': '${questions.length}',
                },
              ),
              color: accent,
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.pill),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: isDark
                ? AppColors.onGradient.withValues(alpha: 0.08)
                : Theme.of(context).colorScheme.outlineVariant,

            valueColor: AlwaysStoppedAnimation<Color>(accent),
          ),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  CefrBadge(
                    level: '${question['level'] ?? 'A1'}',
                    size: CefrBadgeSize.large,
                  ),
                  _TextChip(
                    label: '${question['skill'] ?? 'general'}',
                    icon: Icons.psychology_alt_rounded,
                  ),
                  _TextChip(
                    label: 'assessment.points'.tr(
                      namedArgs: {'points': '${question['points'] ?? 0}'},
                    ),
                    icon: Icons.stars_rounded,
                  ),
                  _TextChip(label: elapsedLabel, icon: Icons.timer_rounded),
                ],
              ),
              const SizedBox(height: 18),
              Text(
                '${question['question'] ?? ''}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  height: 1.25,
                ),
              ),
              const SizedBox(height: 18),
              for (var i = 0; i < options.length; i++) ...[
                TestAnswerOption(
                  index: i,
                  text: options[i],
                  selected: selectedOption == i,
                  onTap: () => onSelectAnswer(questionId, i),
                ),
                if (i != options.length - 1) const SizedBox(height: 10),
              ],
            ],
          ),
        ),
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: currentIndex == 0 ? null : onPrevious,
                child: Text('assessment.previous'.tr()),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: FilledButton.icon(
                onPressed: isSubmitting
                    ? null
                    : isLast
                    ? onSubmit
                    : onNext,
                icon: isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: AppSpacing.lg,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(
                        isLast
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                      ),
                label: Text(
                  isLast
                      ? 'assessment.submitTest'.tr()
                      : 'assessment.next'.tr(),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: AppColors.onGradient,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ResultState extends StatelessWidget {
  const _ResultState({required this.result, required this.onRetake});

  final Map<String, dynamic> result;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    final level = '${result['assessed_level'] ?? 'A1'}';
    final score = result['score_percentage'] ?? 0;
    final correct = result['correct_count'] ?? 0;
    final total = result['total_questions'] ?? 0;

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(
              color: isDark
                  ? Theme.of(context).colorScheme.outlineVariant
                  : Theme.of(context).colorScheme.outlineVariant,
            ),
          ),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent.withValues(alpha: 0.14),
                ),
                child: Icon(
                  Icons.emoji_events_rounded,
                  color: accent,
                  size: 34,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                'assessment.testCompleted'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'assessment.resultSubtitle'.tr(),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: AppColorRoles.textSecondary(isDark),
                  height: 1.35,
                ),
              ),
              const SizedBox(height: 20),
              CefrBadge(
                level: level,
                size: CefrBadgeSize.large,
                outlined: true,
              ),
              const SizedBox(height: 10),
              Text(
                'assessment.yourLevelIs'.tr(namedArgs: {'level': level}),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: _ResultMetric(
                      label: 'assessment.score'.tr(),
                      value: '$score%',
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _ResultMetric(
                      label: 'assessment.correct'.tr(),
                      value: '$correct/$total',
                    ),
                  ),
                ],
              ),
              if (result['rank_name'] != null) ...[
                const SizedBox(height: 10),
                _ResultMetric(
                  label: 'assessment.rank'.tr(),
                  value: '${result['rank_name']}',
                ),
              ],
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onRetake,
                      child: Text('assessment.retakeTest'.tr()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: AppColors.onGradient,
                      ),
                      child: Text('common.done'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ResultMetric extends StatelessWidget {
  const _ResultMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: 14,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkInput : AppColors.grey50,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        children: [
          Text(
            value,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.error_outline_rounded,
      title: 'assessment.loadFailed'.tr(),
      message: message,
      actionLabel: 'common.retry'.tr(),
      onAction: onRetry,
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return _CenteredState(
      icon: Icons.quiz_rounded,
      title: 'assessment.noQuestions'.tr(),
      message: 'assessment.noQuestionsSubtitle'.tr(),
      actionLabel: 'common.retry'.tr(),
      onAction: onRetry,
    );
  }
}

class _CenteredState extends StatelessWidget {
  const _CenteredState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 44, color: accent),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.1),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _TextChip extends StatelessWidget {
  const _TextChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkInput : AppColors.grey100,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColorRoles.textSecondary(isDark)),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}
