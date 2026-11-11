import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_history_entry.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';

/// Vertical timeline of the learner's CEFR level changes.
///
/// The server records a row only when the level changes, so the first node is
/// derived: the level the learner held before the earliest change, or the
/// current level when nothing has changed yet.
class LevelHistoryTimeline extends StatefulWidget {
  const LevelHistoryTimeline({super.key});

  @override
  State<LevelHistoryTimeline> createState() => _LevelHistoryTimelineState();
}

class _LevelHistoryTimelineState extends State<LevelHistoryTimeline> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProficiencyProvider>().loadHistory();
    });
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProficiencyProvider>();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'profile.levelJourney'.tr(),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          _body(context, provider),
        ],
      ),
    );
  }

  Widget _body(BuildContext context, ProficiencyProvider provider) {
    final theme = Theme.of(context);

    if (provider.historyFailed && !provider.historyLoaded) {
      return Row(
        children: [
          Expanded(
            child: Text(
              'profile.levelJourneyFailed'.tr(),
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          TextButton(
            onPressed: () => provider.loadHistory(force: true),
            child: Text('common.retry'.tr()),
          ),
        ],
      );
    }
    if (!provider.historyLoaded) {
      return const Center(
        child: SizedBox.square(
          dimension: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final history = provider.history;
    final nodes = <_Node>[
      _Node(
        level: history.isEmpty
            ? provider.assessedLevel
            : history.first.previousLevel,
        caption: null,
        startLevel: true,
      ),
      for (final entry in history)
        _Node(level: entry.newLevel, caption: entry, startLevel: false),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < nodes.length; i++)
          _TimelineRow(node: nodes[i], isLast: i == nodes.length - 1),
        if (history.isEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'profile.levelJourneyEmpty'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ],
    );
  }
}

class _Node {
  const _Node({
    required this.level,
    required this.caption,
    required this.startLevel,
  });

  final String level;
  final LevelHistoryEntry? caption;
  final bool startLevel;
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.node, required this.isLast});

  final _Node node;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entry = node.caption;
    final tone = entry == null
        ? theme.colorScheme.primary
        : entry.isPromotion
        ? theme.colorScheme.primary
        : theme.colorScheme.error;

    final subtitle = entry == null
        ? 'profile.levelStart'.tr(namedArgs: {'level': node.level})
        : (entry.isPromotion ? 'profile.levelPromoted' : 'profile.levelDemoted')
              .tr(namedArgs: {'from': entry.previousLevel});

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 44,
            child: Column(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tone.withValues(alpha: 0.12),
                    border: Border.all(color: tone, width: 2),
                  ),
                  child: Text(
                    node.level,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (!isLast)
                  Expanded(
                    child: Container(
                      width: 2,
                      color: theme.colorScheme.outlineVariant,
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(
                left: 12,
                bottom: isLast ? 0 : 20,
                top: 6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    subtitle,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (entry != null)
                    Text(
                      DateFormat.yMMMd().format(entry.triggeredAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
