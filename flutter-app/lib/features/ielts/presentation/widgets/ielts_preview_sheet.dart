import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/ielts_entities.dart';

/// What a test contains, shown before a sitting is created.
///
/// Pops with `true` when the learner chooses to start (or continue) it.
class IeltsPreviewSheet extends StatelessWidget {
  const IeltsPreviewSheet({
    super.key,
    required this.test,
    required this.loadPaper,
    required this.hasSittingInProgress,
  });

  final IeltsTestSummary test;
  final Future<IeltsPaper> Function() loadPaper;
  final bool hasSittingInProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(test.title, style: theme.textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              'ielts.previewTitle'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            // The contents scroll on short screens; the start button stays in view.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (hasSittingInProgress) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          'ielts.previewInProgress'.tr(),
                          style: TextStyle(
                            color: theme.colorScheme.onSecondaryContainer,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    FutureBuilder<IeltsPaper>(
                      future: loadPaper(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Padding(
                            padding: EdgeInsets.symmetric(vertical: 24),
                            child: Center(child: CircularProgressIndicator()),
                          );
                        }
                        if (snapshot.hasError || snapshot.data == null) {
                          return Padding(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            child: Text(
                              'ielts.previewFailed'.tr(),
                              style: TextStyle(color: theme.colorScheme.error),
                            ),
                          );
                        }
                        final sections = snapshot.data!.sections;
                        return Column(
                          children: [
                            for (final section in sections)
                              _SectionRow(section: section),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text(
                  hasSittingInProgress
                      ? 'ielts.previewContinue'.tr()
                      : 'ielts.previewStart'.tr(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section});

  final IeltsSection section;

  static const _icons = {
    IeltsSkill.listening: Icons.headphones_outlined,
    IeltsSkill.reading: Icons.menu_book_outlined,
    IeltsSkill.writing: Icons.edit_outlined,
    IeltsSkill.speaking: Icons.mic_none_outlined,
  };

  String _name() => switch (section.skill) {
    IeltsSkill.listening => 'ielts.skillListening'.tr(),
    IeltsSkill.reading => 'ielts.skillReading'.tr(),
    IeltsSkill.writing => 'ielts.skillWriting'.tr(),
    IeltsSkill.speaking => 'ielts.skillSpeaking'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final details = <String>[
      'ielts.previewParts'.tr(namedArgs: {'count': '${section.parts.length}'}),
      if (section.questionCount > 0)
        'ielts.previewQuestions'.tr(
          namedArgs: {'count': '${section.questionCount}'},
        ),
      if (section.durationMinutes > 0)
        'ielts.previewMinutes'.tr(
          namedArgs: {'count': '${section.durationMinutes}'},
        ),
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_icons[section.skill], color: theme.colorScheme.primary),
      title: Text(_name(), style: theme.textTheme.titleSmall),
      subtitle: Text(details.join(' · ')),
    );
  }
}
