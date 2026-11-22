import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/ielts_entities.dart';
import '../providers/ielts_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

String _titleCase(String key) => key
    .split('_')
    .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
    .join(' ');

String _skillName(String skill) => switch (skill) {
  'listening' => 'ielts.skillListening'.tr(),
  'reading' => 'ielts.skillReading'.tr(),
  'writing' => 'ielts.skillWriting'.tr(),
  'speaking' => 'ielts.skillSpeaking'.tr(),
  _ => _titleCase(skill),
};

String _criterionLabel(String key) => switch (key) {
  'task_achievement' => 'ielts.criteriaTaskAchievement'.tr(),
  'task_response' => 'ielts.criteriaTaskResponse'.tr(),
  'coherence_cohesion' => 'ielts.criteriaCoherenceCohesion'.tr(),
  'lexical_resource' => 'ielts.criteriaLexicalResource'.tr(),
  'grammatical_range_accuracy' => 'ielts.criteriaGrammar'.tr(),
  'fluency_coherence' => 'ielts.criteriaFluencyCoherence'.tr(),
  'pronunciation' => 'ielts.criteriaPronunciation'.tr(),
  _ => _titleCase(key),
};

/// Results. Writing and Speaking arrive later than Listening and Reading —
/// the objective skills are an answer key, the productive ones are a model
/// call each — so this screen shows partial results rather than waiting.
class IeltsResultPage extends StatelessWidget {
  final String attemptId;

  const IeltsResultPage({super.key, required this.attemptId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IeltsProvider>(
      create: (_) => sl<IeltsProvider>()..openResult(attemptId),
      child: _ResultView(attemptId: attemptId),
    );
  }
}

class _ResultView extends StatelessWidget {
  final String attemptId;
  const _ResultView({required this.attemptId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<IeltsProvider>();
    final result = provider.result;

    return Scaffold(
      appBar: AppBar(
        title: Text('ielts.resultTitle'.tr()),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.refreshResult(),
            tooltip: 'ielts.refresh'.tr(),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: result == null
            ? (provider.error != null && !provider.isLoading
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              provider.error!,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            FilledButton(
                              onPressed: () => provider.openResult(attemptId),
                              child: Text('common.retry'.tr()),
                            ),
                          ],
                        ),
                      ),
                    )
                  : const Center(child: CircularProgressIndicator()))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _OverallCard(result: result),
                  const SizedBox(height: AppSpacing.lg),
                  if (result.isAwaitingGrading)
                    Card(
                      color: theme.colorScheme.secondaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                'ielts.awaitingGrading'.tr(),
                                style: TextStyle(
                                  color: theme.colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.sm),
                  ...result.gradings.map((g) => _GradingCard(grading: g)),
                  ...result.review.entries.map(
                    (entry) => _ReviewSection(
                      skill: entry.key,
                      items: entry.value,
                      raw: result.rawScores[entry.key],
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _OverallCard extends StatelessWidget {
  final IeltsResult result;
  const _OverallCard({required this.result});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const order = ['listening', 'reading', 'writing', 'speaking'];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Text(
              result.testTitle ?? 'ielts.defaultTestTitle'.tr(),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              result.overallBand?.toStringAsFixed(1) ?? '—',
              style: theme.textTheme.displayMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              result.overallBand != null
                  ? 'ielts.overallBand'.tr()
                  : 'ielts.overallBandNeedsAll'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Divider(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: order.map((skill) {
                final band = result.bands[skill];
                return Column(
                  children: [
                    Text(
                      band?.toStringAsFixed(1) ?? '—',
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: band == null
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _skillName(skill),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradingCard extends StatelessWidget {
  final IeltsGradingResult grading;
  const _GradingCard({required this.grading});

  String get _label {
    final match = RegExp(
      r'^(writing_task|speaking_part)_(\d+)$',
    ).firstMatch(grading.partKey);
    if (match != null) {
      final n = {'n': match.group(2)!};
      return match.group(1) == 'writing_task'
          ? 'ielts.writingTask'.tr(namedArgs: n)
          : 'ielts.speakingPart'.tr(namedArgs: n);
    }
    return _titleCase(grading.partKey);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (grading.isPending) {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          title: Text(_label),
          subtitle: Text('ielts.beingGraded'.tr()),
        ),
      );
    }

    if (grading.status == 'failed') {
      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: theme.colorScheme.errorContainer,
        child: ListTile(
          leading: const Icon(Icons.error_outline),
          title: Text(_label),
          subtitle: Text('ielts.gradingFailed'.tr()),
        ),
      );
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Row(
          children: [
            Expanded(child: Text(_label, style: theme.textTheme.titleSmall)),
            Text(
              grading.band?.toStringAsFixed(1) ?? '—',
              style: theme.textTheme.titleLarge?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ),
        subtitle: Text(
          'ielts.wordCount'.tr(namedArgs: {'count': '${grading.wordCount}'}),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ...grading.criteria.entries.map((entry) {
            final label = _criterionLabel(entry.key);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodySmall),
                  ),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: (entry.value / 9).clamp(0.0, 1.0),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  SizedBox(
                    width: 28,
                    child: Text(
                      entry.value.toStringAsFixed(1),
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            );
          }),
          if (grading.reasoning != null && grading.reasoning!.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text(grading.reasoning!, style: theme.textTheme.bodySmall),
          ],
          if (grading.improvements.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('ielts.raiseBand'.tr(), style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            ...grading.improvements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item', style: theme.textTheme.bodySmall),
              ),
            ),
          ],
          if (grading.corrections.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.md),
            Text('ielts.corrections'.tr(), style: theme.textTheme.labelLarge),
            const SizedBox(height: AppSpacing.xs),
            ...grading.corrections.map(
              (c) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      c['original'] ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        decoration: TextDecoration.lineThrough,
                        color: theme.colorScheme.error,
                      ),
                    ),
                    Text(
                      c['corrected'] ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ReviewSection extends StatelessWidget {
  final String skill;
  final List<IeltsReviewItem> items;
  final Map<String, int>? raw;

  const _ReviewSection({required this.skill, required this.items, this.raw});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (items.isEmpty) return const SizedBox.shrink();

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        title: Text(_skillName(skill), style: theme.textTheme.titleSmall),
        subtitle: raw != null
            ? Text(
                'ielts.correctCount'.tr(
                  namedArgs: {
                    'raw': '${raw!['raw']}',
                    'total': '${raw!['total']}',
                  },
                ),
              )
            : null,
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: items.map((item) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  item.isCorrect ? Icons.check_circle : Icons.cancel,
                  size: 18,
                  color: item.isCorrect
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${item.number ?? ''}. ${item.prompt}',
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'ielts.yourAnswer'.tr(
                          namedArgs: {
                            'answer': item.userAnswer?.isNotEmpty == true
                                ? item.userAnswer!
                                : 'ielts.blankAnswer'.tr(),
                          },
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!item.isCorrect)
                        Text(
                          'ielts.correctAnswer'.tr(
                            namedArgs: {'answer': item.correctAnswer ?? ''},
                          ),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
