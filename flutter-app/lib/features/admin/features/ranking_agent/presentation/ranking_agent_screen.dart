import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/growth_form.dart';
import '../../../shared/widgets/growth_job_actions.dart';
import '../../../shared/widgets/growth_state_body.dart';
import '../data/ranking_agent_repository.dart';

class RankingAgentScreen extends StatefulWidget {
  const RankingAgentScreen({super.key, this.repository});

  final RankingAgentRepository? repository;

  @override
  State<RankingAgentScreen> createState() => _RankingAgentScreenState();
}

class _RankingAgentScreenState extends State<RankingAgentScreen> {
  late final RankingAgentRepository _repo =
      widget.repository ?? RankingAgentRepository();
  List<RankingAgentJob> _jobs = const [];
  bool _loading = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobs = await _repo.listJobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(Object error, String fallbackKey) {
    if (!mounted) return;
    final api = AdminApiError.from(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          api.isForbidden || api.isFeatureOff
              ? api.message.resolve()
              : fallbackKey.tr(),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CreateRankingJobSheet(),
    );
    if (payload == null) return;
    try {
      await _repo.createJob(payload);
      await _load();
    } catch (e) {
      _toast(e, 'adminGrowth.ranking.createFailed');
    }
  }

  Future<void> _preview(RankingAgentJob job) async {
    try {
      final preview = await _repo.getPreview(job.id);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => RankingPreviewSheet(job: job, preview: preview),
      );
    } catch (e) {
      _toast(e, 'adminGrowth.ranking.previewMissing');
    }
  }

  Future<void> _action(RankingAgentJob job, String action) async {
    if (action == 'apply') {
      final impactful =
          job.jobType == 'league_reset' || job.jobType == 'xp_event';
      final ok = await confirmApply(
        context,
        title: 'adminGrowth.ranking.applyTitle'.tr(),
        body: impactful
            ? 'adminGrowth.ranking.applyImpact'.tr()
            : 'adminGrowth.ranking.applyWrites'.tr(),
      );
      if (!ok) return;
    } else if (action == 'cancel') {
      final ok = await confirmCancel(
        context,
        title: 'adminGrowth.ranking.cancelTitle'.tr(),
        body: 'adminGrowth.ranking.cancelBody'.tr(),
      );
      if (!ok) return;
    }
    try {
      if (action == 'apply') await _repo.applyJob(job.id);
      if (action == 'cancel') await _repo.cancelJob(job.id);
      if (action == 'retry') await _repo.retryJob(job.id);
      await _load();
    } catch (e) {
      _toast(e, 'adminGrowth.common.actionFailed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AdminPermissions>();
    final canCreate = perms.can('ranking:create');
    final canWrite = perms.can('ranking:create');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          icon: const Icon(Icons.menu_rounded),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('adminGrowth.ranking.title'.tr()),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'adminGrowth.common.refresh'.tr(),
          ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add),
              label: Text('adminGrowth.ranking.create'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: GrowthStateBody(
          isLoading: _loading,
          hasData: _jobs.isNotEmpty,
          error: _error,
          onRetry: _load,
          emptyTitleKey: 'adminGrowth.ranking.empty',
          emptyIcon: Icons.emoji_events_outlined,
          builder: (context) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              100,
            ),
            children: [
              Text(
                'adminGrowth.ranking.subtitle'.tr(),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              for (final job in _jobs)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.md),
                  child: RankingJobCard(
                    job: job,
                    canWrite: canWrite,
                    onPreview: () => _preview(job),
                    onAction: (v) => _action(job, v),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

String rankingTypeLabel(String value) => switch (value) {
  'league_reset' => 'adminGrowth.ranking.typeLeague'.tr(),
  'xp_event' => 'adminGrowth.ranking.typeXp'.tr(),
  _ => 'adminGrowth.ranking.typeAchievement'.tr(),
};

String _date(String value) {
  final date = DateTime.tryParse(value)?.toLocal();
  return date == null ? '—' : intl.DateFormat('dd/MM/yyyy HH:mm').format(date);
}

class RankingJobCard extends StatelessWidget {
  const RankingJobCard({
    super.key,
    required this.job,
    required this.onPreview,
    required this.onAction,
    this.canWrite = true,
  });

  final RankingAgentJob job;
  final VoidCallback onPreview;
  final ValueChanged<String> onAction;
  final bool canWrite;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final icon = switch (job.jobType) {
      'league_reset' => Icons.rotate_left_rounded,
      'xp_event' => Icons.bolt_rounded,
      _ => Icons.military_tech_rounded,
    };
    const min = Size(kMinTapTarget, kMinTapTarget);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: AppRadius.mdAll,
                ),
                child: Icon(icon, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      rankingTypeLabel(job.jobType),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      _date(job.createdAt),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              StatusPill(
                label: job.status.replaceAll('_', ' '),
                tone: jobStatusTone(job.status),
              ),
            ],
          ),
          if (job.isActive) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: job.progressPercent / 100),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${job.progress['stage'] ?? ''} • ${job.progressPercent}%',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (job.warnings.isNotEmpty || job.blockingErrors.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              job.blockingErrors.isNotEmpty
                  ? 'adminGrowth.ranking.blockingErrors'.tr(
                      args: ['${job.blockingErrors.length}'],
                    )
                  : 'adminGrowth.ranking.warnings'.tr(
                      args: ['${job.warnings.length}'],
                    ),
              style: theme.textTheme.bodySmall?.copyWith(
                color: job.blockingErrors.isNotEmpty
                    ? scheme.error
                    : context.statusWarning,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (job.status == 'preview_ready')
                TextButton.icon(
                  onPressed: onPreview,
                  icon: const Icon(Icons.visibility_outlined),
                  label: Text('adminGrowth.ranking.preview'.tr()),
                  style: TextButton.styleFrom(minimumSize: min),
                ),
            ],
          ),
          if (canWrite)
            GrowthJobActions(
              onApply: job.canApply ? () => onAction('apply') : null,
              onCancel: job.isActive && job.status != 'applying'
                  ? () => onAction('cancel')
                  : null,
              onRetry: job.status == 'failed' ? () => onAction('retry') : null,
            ),
        ],
      ),
    );
  }
}

extension on BuildContext {
  Color get statusWarning =>
      Theme.of(this).extension<AppStatusColors>()!.warning;
}

class CreateRankingJobSheet extends StatefulWidget {
  const CreateRankingJobSheet({super.key});

  @override
  State<CreateRankingJobSheet> createState() => _CreateRankingJobSheetState();
}

class _CreateRankingJobSheetState extends State<CreateRankingJobSheet> {
  static const _leagues = [
    'bronze',
    'silver',
    'gold',
    'platinum',
    'sapphire',
    'ruby',
    'amethyst',
    'master',
  ];
  static const _cefr = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  String type = 'league_reset',
      target = 'all',
      targetLeague = 'gold',
      targetCefr = 'B1';
  bool ai = false, _invalid = false;
  final week = TextEditingController(),
      name = TextEditingController(text: 'Weekend Boost'),
      multiplier = TextEditingController(text: '2'),
      duration = TextEditingController(text: '48'),
      slugs = TextEditingController(),
      streak = TextEditingController(),
      vocab = TextEditingController();
  final leagues = <String>{}, cefr = <String>{};

  @override
  void dispose() {
    for (final c in [week, name, multiplier, duration, slugs, streak, vocab]) {
      c.dispose();
    }
    super.dispose();
  }

  Map<String, dynamic>? _payload() {
    Map<String, dynamic> config;
    if (type == 'league_reset') {
      config = {
        if (week.text.trim().isNotEmpty) 'week_start': week.text.trim(),
      };
    } else if (type == 'xp_event') {
      final multiplierValue = double.tryParse(multiplier.text);
      final durationValue = int.tryParse(duration.text);
      if (name.text.trim().isEmpty ||
          multiplierValue == null ||
          !multiplierValue.isFinite ||
          multiplierValue < 1.1 ||
          multiplierValue > 5 ||
          durationValue == null ||
          durationValue < 1 ||
          durationValue > 168) {
        return null;
      }
      config = {
        'name': name.text.trim(),
        'multiplier': multiplierValue,
        'duration_hours': durationValue,
        'target': target == 'league'
            ? 'league:$targetLeague'
            : target == 'cefr'
            ? 'cefr:$targetCefr'
            : 'all',
      };
    } else {
      final values = slugs.text
          .split(RegExp(r'[\s,]+'))
          .where((value) => value.isNotEmpty)
          .toList();
      final streakValue = streak.text.isEmpty
          ? null
          : int.tryParse(streak.text);
      final vocabValue = vocab.text.isEmpty ? null : int.tryParse(vocab.text);
      if (values.isEmpty ||
          (streak.text.isNotEmpty &&
              (streakValue == null || streakValue < 0)) ||
          (vocab.text.isNotEmpty && (vocabValue == null || vocabValue < 0))) {
        return null;
      }
      config = {
        'achievement_slugs': values,
        'criteria': {
          if (streakValue != null) 'min_streak': streakValue,
          if (vocabValue != null) 'min_vocabulary_mastered': vocabValue,
          if (leagues.isNotEmpty) 'leagues': leagues.toList(),
          if (cefr.isNotEmpty) 'cefr_levels': cefr.toList(),
        },
      };
    }
    return {'job_type': type, 'config': config, 'use_ai_insights': ai};
  }

  void _submit() {
    final value = _payload();
    if (value == null) {
      setState(() => _invalid = true);
      return;
    }
    Navigator.pop(context, value);
  }

  @override
  Widget build(BuildContext context) => GrowthFormSheet(
    title: 'adminGrowth.ranking.createTitle'.tr(),
    onSave: _submit,
    children: [
      GrowthDropdown(
        label: 'adminGrowth.ranking.jobType'.tr(),
        value: type,
        options: const ['league_reset', 'xp_event', 'achievement_batch'],
        optionLabel: rankingTypeLabel,
        onChanged: (v) => setState(() => type = v),
      ),
      if (type == 'league_reset')
        GrowthField(
          controller: week,
          label: 'adminGrowth.ranking.weekStart'.tr(),
        ),
      if (type == 'xp_event') ...[
        GrowthField(
          controller: name,
          label: 'adminGrowth.ranking.eventName'.tr(),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GrowthField(
                controller: multiplier,
                number: true,
                label: 'adminGrowth.ranking.multiplier'.tr(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: GrowthField(
                controller: duration,
                number: true,
                label: 'adminGrowth.ranking.hours'.tr(),
              ),
            ),
          ],
        ),
        GrowthDropdown(
          label: 'adminGrowth.ranking.audience'.tr(),
          value: target,
          options: const ['all', 'league', 'cefr'],
          optionLabel: (v) => switch (v) {
            'league' => 'adminGrowth.ranking.audienceLeague'.tr(),
            'cefr' => 'adminGrowth.ranking.audienceCefr'.tr(),
            _ => 'adminGrowth.ranking.audienceAll'.tr(),
          },
          onChanged: (v) => setState(() => target = v),
        ),
        if (target == 'league')
          GrowthDropdown(
            label: 'adminGrowth.ranking.leagues'.tr(),
            value: targetLeague,
            options: _leagues,
            onChanged: (v) => setState(() => targetLeague = v),
          ),
        if (target == 'cefr')
          GrowthDropdown(
            label: 'adminGrowth.ranking.cefr'.tr(),
            value: targetCefr,
            options: _cefr,
            onChanged: (v) => setState(() => targetCefr = v),
          ),
      ],
      if (type == 'achievement_batch') ...[
        GrowthField(
          controller: slugs,
          lines: 2,
          label: 'adminGrowth.ranking.slugs'.tr(),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GrowthField(
                controller: streak,
                number: true,
                label: 'adminGrowth.ranking.minStreak'.tr(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: GrowthField(
                controller: vocab,
                number: true,
                label: 'adminGrowth.ranking.minVocab'.tr(),
              ),
            ),
          ],
        ),
        _Choices(
          labelKey: 'adminGrowth.ranking.leagues',
          values: _leagues,
          selected: leagues,
          changed: () => setState(() {}),
        ),
        _Choices(
          labelKey: 'adminGrowth.ranking.cefr',
          values: _cefr,
          selected: cefr,
          changed: () => setState(() {}),
        ),
      ],
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: ai,
        onChanged: (v) => setState(() => ai = v),
        title: Text('adminGrowth.ranking.aiInsights'.tr()),
        subtitle: Text('adminGrowth.ranking.aiInsightsBody'.tr()),
      ),
      if (_invalid)
        Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'adminGrowth.ranking.checkFields'.tr(),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );
}

class _Choices extends StatelessWidget {
  const _Choices({
    required this.labelKey,
    required this.values,
    required this.selected,
    required this.changed,
  });

  final String labelKey;
  final List<String> values;
  final Set<String> selected;
  final VoidCallback changed;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelKey.tr(), style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.sm,
          children: [
            for (final value in values)
              FilterChip(
                label: Text(value),
                selected: selected.contains(value),
                onSelected: (_) {
                  selected.contains(value)
                      ? selected.remove(value)
                      : selected.add(value);
                  changed();
                },
              ),
          ],
        ),
      ],
    ),
  );
}

class RankingPreviewSheet extends StatelessWidget {
  const RankingPreviewSheet({
    super.key,
    required this.job,
    required this.preview,
  });

  final RankingAgentJob job;
  final RankingAgentPreview preview;

  @override
  Widget build(BuildContext context) {
    final a = preview.artifact;
    final entries = switch (job.jobType) {
      'league_reset' => {
        'adminGrowth.ranking.pTotalParticipants': a['total_participants'] ?? 0,
        'adminGrowth.ranking.pPromotions':
            (a['promotions'] as List?)?.length ?? 0,
        'adminGrowth.ranking.pDemotions':
            (a['demotions'] as List?)?.length ?? 0,
        'adminGrowth.ranking.pWeek': a['week'] ?? '—',
      },
      'xp_event' => {
        'adminGrowth.ranking.pUsersAffected': a['target_user_count'] ?? 0,
        'adminGrowth.ranking.pXpDelta': a['estimated_total_xp_delta'] ?? 0,
        'adminGrowth.ranking.pMultiplier': a['multiplier'] ?? '—',
        'adminGrowth.ranking.pDuration': '${a['duration_hours'] ?? '—'}h',
      },
      _ => {
        'adminGrowth.ranking.pUsersAffected': a['total_users_affected'] ?? 0,
        'adminGrowth.ranking.pXpAwarded': a['total_xp_to_award'] ?? 0,
        'adminGrowth.ranking.pAchievements':
            (a['achievements'] as List?)?.length ?? 0,
      },
    };
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'adminGrowth.ranking.preview'.tr(),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            for (final e in entries.entries)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(e.key.tr()),
                trailing: Text(
                  '${e.value}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            if (preview.warnings.isNotEmpty)
              Text(
                'adminGrowth.ranking.warningsLabel'.tr(
                  args: [preview.warnings.join('\n')],
                ),
                style: TextStyle(color: context.statusWarning),
              ),
            if (preview.blockingErrors.isNotEmpty)
              Text(
                'adminGrowth.ranking.blockingLabel'.tr(
                  args: [preview.blockingErrors.join('\n')],
                ),
                style: TextStyle(color: scheme.error),
              ),
            const SizedBox(height: AppSpacing.md),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('adminGrowth.ranking.close'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
