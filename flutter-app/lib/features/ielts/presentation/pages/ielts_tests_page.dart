import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/di/service_locator.dart';
import '../../domain/entities/ielts_entities.dart';
import '../providers/ielts_provider.dart';
import 'ielts_sitting_page.dart';
import 'ielts_result_page.dart';

class IeltsTestsPage extends StatelessWidget {
  const IeltsTestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IeltsProvider>(
      create: (_) => sl<IeltsProvider>()
        ..loadTests()
        ..loadHistory(),
      child: const _IeltsTestsView(),
    );
  }
}

class _IeltsTestsView extends StatelessWidget {
  const _IeltsTestsView();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<IeltsProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('IELTS Practice Tests')),
      body: RefreshIndicator(
        onRefresh: () async {
          await provider.loadTests();
          await provider.loadHistory();
        },
        child: provider.isLoading && provider.tests.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (provider.error != null)
                    Card(
                      color: theme.colorScheme.errorContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          provider.error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                  if (provider.history.isNotEmpty) ...[
                    Text('Your results', style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    ...provider.history
                        .take(3)
                        .map((attempt) => _HistoryTile(attempt: attempt)),
                    const SizedBox(height: 24),
                  ],
                  Text('Available tests', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 8),
                  if (provider.tests.isEmpty && !provider.isLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 48),
                      child: Center(
                        child: Text(
                          'No published tests yet.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                  ...provider.tests.map((test) => _TestCard(test: test)),
                ],
              ),
      ),
    );
  }
}

class _TestCard extends StatelessWidget {
  final IeltsTestSummary test;
  const _TestCard({required this.test});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => IeltsSittingPage(test: test),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(test.title, style: theme.textTheme.titleMedium),
                  ),
                  Chip(
                    label: Text(test.isAcademic ? 'Academic' : 'General'),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (test.description != null && test.description!.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  test.description!,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Wrap(
                spacing: 16,
                runSpacing: 4,
                children: [
                  _Meta(
                    icon: Icons.help_outline,
                    label: '${test.questionCount} questions',
                  ),
                  _Meta(
                    icon: Icons.schedule,
                    label: '${test.durationMinutes} min',
                  ),
                  if (test.targetBand != null)
                    _Meta(
                      icon: Icons.flag_outlined,
                      label: 'Band ${test.targetBand}',
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final IconData icon;
  final String label;
  const _Meta({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final Map<String, dynamic> attempt;
  const _HistoryTile({required this.attempt});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final overall = attempt['overall_band'];
    final status = attempt['status']?.toString() ?? '';
    final title = attempt['test_title']?.toString() ?? 'IELTS test';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          status == 'graded'
              ? 'Graded'
              : status == 'submitted'
              ? 'Writing and Speaking still being graded'
              : 'In progress',
        ),
        trailing: overall != null
            ? Text(
                overall.toString(),
                style: theme.textTheme.titleLarge?.copyWith(
                  color: theme.colorScheme.primary,
                ),
              )
            : const Icon(Icons.chevron_right),
        onTap: () {
          final id = attempt['attempt_id']?.toString();
          if (id == null) return;
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => IeltsResultPage(attemptId: id),
            ),
          );
        },
      ),
    );
  }
}
