import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/level/domain/entities/level_history_entry.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';

/// The learner's CEFR path as one row of chips, the latest change in one line.
///
/// A level changes only when the learner passes a level test, so the path is
/// short. The server records a row only on a change, so the first chip is
/// derived: the level held before the earliest change, or the current level
/// when nothing has changed yet.
class LevelHistoryTimeline extends StatefulWidget {
  const LevelHistoryTimeline({super.key});

  @override
  State<LevelHistoryTimeline> createState() => _LevelHistoryTimelineState();
}

class _LevelHistoryTimelineState extends State<LevelHistoryTimeline> {
  static const _maxSteps = 6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<ProficiencyProvider>().loadHistory();
    });
  }

  Future<void> _takeTest() async {
    final promoted = await Navigator.pushNamed(context, '/level-exam');
    if (!mounted) return;
    // A pass already ran LevelSync; a fail still changed the cooldown.
    if (promoted != true) {
      await context.read<ProficiencyProvider>().refreshAfterLevelChange();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ProficiencyProvider>();
    final theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
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
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),
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
    final steps = _steps(history, provider.assessedLevel);
    final shown = steps.length > _maxSteps
        ? steps.sublist(steps.length - _maxSteps)
        : steps;
    final next = provider.nextLevel;
    final ready = next != null && next.qualifies && next.level != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: steps.map((s) => s.level).join(' → '),
          excludeSemantics: true,
          child: Wrap(
            spacing: 4,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (steps.length > shown.length)
                Text('…', style: theme.textTheme.titleMedium),
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0 || steps.length > shown.length)
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: theme.colorScheme.outline,
                  ),
                _StepChip(step: shown[i], current: i == shown.length - 1),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _lastChange(history, provider.assessedLevel),
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 10),
        if (ready)
          _ReadyRow(level: next.level!, onTake: _takeTest)
        else
          Text(
            'profile.levelTestRule'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
      ],
    );
  }

  static List<_Step> _steps(List<LevelHistoryEntry> history, String assessed) {
    final steps = <_Step>[
      _Step(history.isEmpty ? assessed : history.first.previousLevel, false),
    ];
    for (final entry in history) {
      if (entry.newLevel == steps.last.level) continue;
      steps.add(
        _Step(entry.newLevel, !entry.isPromotion, chosen: entry.isSelfSet),
      );
    }
    return steps;
  }

  static String _lastChange(List<LevelHistoryEntry> history, String assessed) {
    if (history.isEmpty) {
      return 'profile.levelStart'.tr(namedArgs: {'level': assessed});
    }
    final entry = history.last;
    final text = entry.isSelfSet
        ? 'profile.levelSelfSet'.tr(namedArgs: {'level': entry.newLevel})
        : entry.isInitial
        ? 'profile.levelPlaced'.tr(namedArgs: {'level': entry.newLevel})
        : (entry.isPromotion ? 'profile.levelPromoted' : 'profile.levelDemoted')
              .tr(namedArgs: {'from': entry.previousLevel});
    return '$text · ${DateFormat.yMMMd().format(entry.triggeredAt)}';
  }
}

class _Step {
  const _Step(this.level, this.down, {this.chosen = false});

  final String level;
  final bool down;

  /// Picked by the learner rather than reached through a test.
  final bool chosen;
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.step, required this.current});

  final _Step step;
  final bool current;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tone = step.chosen
        ? scheme.outline
        : step.down
        ? scheme.error
        : scheme.primary;
    final onTone = step.chosen
        ? scheme.surface
        : step.down
        ? scheme.onError
        : scheme.onPrimary;

    return Container(
      constraints: const BoxConstraints(minWidth: 44, minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: current ? tone : tone.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: tone, width: 1.5),
      ),
      child: Text(
        step.level,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: current ? onTone : tone,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

class _ReadyRow extends StatelessWidget {
  const _ReadyRow({required this.level, required this.onTake});

  final String level;
  final VoidCallback onTake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'profile.levelTestReady'.tr(namedArgs: {'level': level}),
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: onTake,
            style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
            child: Text('profile.levelTestTake'.tr()),
          ),
        ],
      ),
    );
  }
}
