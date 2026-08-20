import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/ielts_entities.dart';
import '../providers/ielts_provider.dart';

/// Results. Writing and Speaking arrive later than Listening and Reading —
/// the objective skills are an answer key, the productive ones are a model
/// call each — so this screen shows partial results rather than waiting.
class IeltsResultPage extends StatelessWidget {
  final String attemptId;
  final IeltsProvider? existingProvider;

  const IeltsResultPage({
    super.key,
    required this.attemptId,
    this.existingProvider,
  });

  @override
  Widget build(BuildContext context) {
    if (existingProvider != null) {
      return ChangeNotifierProvider<IeltsProvider>.value(
        value: existingProvider!,
        child: const _ResultView(),
      );
    }
    return ChangeNotifierProvider<IeltsProvider>(
      create: (_) => sl<IeltsProvider>()..openResult(attemptId),
      child: const _ResultView(),
    );
  }
}

class _ResultView extends StatelessWidget {
  const _ResultView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<IeltsProvider>();
    final result = provider.result;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Test result'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => provider.refreshResult(),
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: result == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _OverallCard(result: result),
                const SizedBox(height: 16),
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
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Writing and Speaking are being graded. Pull refresh in a moment.',
                              style: TextStyle(
                                color: theme.colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 8),
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
              result.testTitle ?? 'IELTS mock test',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              result.overallBand?.toStringAsFixed(1) ?? '—',
              style: theme.textTheme.displayMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              result.overallBand != null
                  ? 'Overall band'
                  : 'Overall band needs all four skills',
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
                      skill[0].toUpperCase() + skill.substring(1, 4),
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
    final parts = grading.partKey.split('_');
    return parts.map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1)).join(' ');
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
          subtitle: const Text('Being graded…'),
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
          subtitle: const Text('Grading failed — your answer is saved and can be re-graded.'),
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
        subtitle: Text('${grading.wordCount} words'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          ...grading.criteria.entries.map((entry) {
            final label = entry.key
                .split('_')
                .map((p) => p.isEmpty ? p : p[0].toUpperCase() + p.substring(1))
                .join(' ');
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(label, style: theme.textTheme.bodySmall)),
                  SizedBox(
                    width: 120,
                    child: LinearProgressIndicator(
                      value: (entry.value / 9).clamp(0.0, 1.0),
                      minHeight: 6,
                    ),
                  ),
                  const SizedBox(width: 8),
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
            const SizedBox(height: 12),
            Text(grading.reasoning!, style: theme.textTheme.bodySmall),
          ],
          if (grading.improvements.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('To raise your band', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
            ...grading.improvements.map(
              (item) => Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text('• $item', style: theme.textTheme.bodySmall),
              ),
            ),
          ],
          if (grading.corrections.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('Corrections', style: theme.textTheme.labelLarge),
            const SizedBox(height: 4),
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
        title: Text(
          skill[0].toUpperCase() + skill.substring(1),
          style: theme.textTheme.titleSmall,
        ),
        subtitle: raw != null
            ? Text('${raw!['raw']} / ${raw!['total']} correct')
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
                const SizedBox(width: 8),
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
                        'Your answer: ${item.userAnswer?.isNotEmpty == true ? item.userAnswer : "(blank)"}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!item.isCorrect)
                        Text(
                          'Correct: ${item.correctAnswer ?? ""}',
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
