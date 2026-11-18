import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/growth_form.dart';
import '../../../shared/widgets/growth_job_actions.dart';
import '../../../shared/widgets/growth_state_body.dart';
import '../data/notification_campaign_repository.dart';

class NotificationCampaignScreen extends StatefulWidget {
  const NotificationCampaignScreen({super.key, this.repository});

  final NotificationCampaignRepository? repository;

  @override
  State<NotificationCampaignScreen> createState() =>
      _NotificationCampaignScreenState();
}

class _NotificationCampaignScreenState
    extends State<NotificationCampaignScreen> {
  late final NotificationCampaignRepository _repository =
      widget.repository ?? NotificationCampaignRepository();
  List<NotificationCampaignJob> _jobs = const [];
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
      final jobs = await _repository.getJobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _toast(
    Object error,
    String fallbackKey, {
    List<String> args = const [],
  }) {
    if (!mounted) return;
    final api = AdminApiError.from(error);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          api.isForbidden || api.isFeatureOff
              ? api.message.resolve()
              : fallbackKey.tr(args: args),
        ),
      ),
    );
  }

  Future<void> _create() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CreateCampaignSheet(),
    );
    if (payload == null) return;
    try {
      final job = await _repository.createJob(payload);
      if (mounted) setState(() => _jobs = [job, ..._jobs]);
    } catch (e) {
      _toast(e, 'adminGrowth.campaign.createFailed');
    }
  }

  Future<void> _action(NotificationCampaignJob job, String action) async {
    if (action == 'apply' &&
        !await confirmApply(
          context,
          title: 'adminGrowth.campaign.applyTitle'.tr(),
          body: 'adminGrowth.campaign.applyBody'.tr(),
        )) {
      return;
    }
    if (!mounted) return;
    if (action == 'cancel' &&
        !await confirmCancel(
          context,
          title: 'adminGrowth.campaign.cancelTitle'.tr(),
          body: 'adminGrowth.campaign.cancelBody'.tr(),
        )) {
      return;
    }
    try {
      final updated = switch (action) {
        'apply' => await _repository.apply(job.id),
        'cancel' => await _repository.cancel(job.id),
        _ => await _repository.retry(job.id),
      };
      if (mounted) {
        setState(
          () =>
              _jobs = [for (final j in _jobs) j.id == updated.id ? updated : j],
        );
      }
    } catch (e) {
      _toast(
        e,
        'adminGrowth.jobs.actionFailed',
        args: ['adminGrowth.jobs.$action'.tr().toLowerCase()],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AdminPermissions>();
    final canCreate = perms.can('notifications:create');
    final canWrite = perms.can('notifications:create');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          icon: const Icon(Icons.menu_rounded),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('adminGrowth.campaign.title'.tr()),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: Text('adminGrowth.campaign.create'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: GrowthStateBody(
          isLoading: _loading,
          hasData: _jobs.isNotEmpty,
          error: _error,
          onRetry: _load,
          emptyTitleKey: 'adminGrowth.campaign.empty',
          emptyIcon: Icons.campaign_outlined,
          builder: (_) => ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              96,
            ),
            itemCount: _jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.md),
            itemBuilder: (_, i) => CampaignCard(
              job: _jobs[i],
              canWrite: canWrite,
              onAction: (a) => _action(_jobs[i], a),
            ),
          ),
        ),
      ),
    );
  }
}

class CampaignCard extends StatelessWidget {
  const CampaignCard({
    super.key,
    required this.job,
    required this.onAction,
    this.canWrite = true,
  });

  final NotificationCampaignJob job;
  final ValueChanged<String> onAction;
  final bool canWrite;

  IconData get _icon => switch (job.jobType) {
    'in_app_broadcast' => Icons.message_outlined,
    'scheduled_push' => Icons.schedule_outlined,
    _ => Icons.notifications_outlined,
  };

  String _date(String value) {
    final d = DateTime.tryParse(value)?.toLocal();
    return d == null
        ? '—'
        : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(
          color: job.needsAttention ? scheme.primary : scheme.outlineVariant,
          width: 0.5,
        ),
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
                child: Icon(_icon, color: scheme.primary),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      job.jobType.replaceAll('_', ' '),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'adminGrowth.jobs.created'.tr(
                        args: [_date(job.createdAt)],
                      ),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (job.scheduledAt != null)
                      Text(
                        'adminGrowth.jobs.scheduled'.tr(
                          args: [_date(job.scheduledAt!)],
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
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
          if (job.needsAttention) ...[
            const SizedBox(height: AppSpacing.md),
            LinearProgressIndicator(value: job.progressPercent / 100),
          ],
          if (job.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              job.errorMessage!,
              style: theme.textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ],
          if (canWrite)
            GrowthJobActions(
              onRetry: job.canRetry ? () => onAction('retry') : null,
              onCancel: job.canCancel ? () => onAction('cancel') : null,
              onApply: job.canApply ? () => onAction('apply') : null,
            ),
        ],
      ),
    );
  }
}

class CreateCampaignSheet extends StatefulWidget {
  const CreateCampaignSheet({super.key});

  @override
  State<CreateCampaignSheet> createState() => _CreateCampaignSheetState();
}

class _CreateCampaignSheetState extends State<CreateCampaignSheet> {
  final _title = TextEditingController(),
      _body = TextEditingController(),
      _type = TextEditingController(text: 'campaign'),
      _link = TextEditingController(),
      _minStreak = TextEditingController(),
      _inactiveDays = TextEditingController();
  NotificationCampaignJobType _jobType =
      NotificationCampaignJobType.targetedPush;
  bool _segment = false, _ai = false, _submitted = false;
  DateTime? _sendAt;
  final Set<String> _leagues = {}, _levels = {};
  static const leagues = [
    'bronze',
    'silver',
    'gold',
    'platinum',
    'sapphire',
    'ruby',
    'amethyst',
    'master',
  ];
  static const levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void dispose() {
    for (final c in [_title, _body, _type, _link, _minStreak, _inactiveDays]) {
      c.dispose();
    }
    super.dispose();
  }

  String _typeLabel(NotificationCampaignJobType t) => switch (t) {
    NotificationCampaignJobType.targetedPush =>
      'adminGrowth.campaign.typeTargeted'.tr(),
    NotificationCampaignJobType.inAppBroadcast =>
      'adminGrowth.campaign.typeInApp'.tr(),
    NotificationCampaignJobType.scheduledPush =>
      'adminGrowth.campaign.typeScheduled'.tr(),
  };

  void _toggle(Set<String> values, String value) => setState(
    () => values.contains(value) ? values.remove(value) : values.add(value),
  );

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(
      context: context,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDate: _sendAt ?? DateTime.now(),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_sendAt ?? DateTime.now()),
    );
    if (time != null && mounted) {
      setState(
        () => _sendAt = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  String? _req(TextEditingController c) => _submitted && c.text.trim().isEmpty
      ? 'adminGrowth.campaign.required'.tr()
      : null;

  String? _num(TextEditingController c) =>
      _submitted && c.text.isNotEmpty && int.tryParse(c.text) == null
      ? 'adminGrowth.campaign.numberRequired'.tr()
      : null;

  void _submit() {
    setState(() => _submitted = true);
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) return;
    if (_segment &&
        ((_minStreak.text.isNotEmpty &&
                int.tryParse(_minStreak.text) == null) ||
            (_inactiveDays.text.isNotEmpty &&
                int.tryParse(_inactiveDays.text) == null))) {
      return;
    }
    if (_jobType == NotificationCampaignJobType.scheduledPush &&
        _sendAt == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('adminGrowth.campaign.needTime'.tr())),
      );
      return;
    }
    final filters = <String, dynamic>{'has_fcm_token': true};
    if (_segment) {
      if (_leagues.isNotEmpty) filters['leagues'] = _leagues.toList();
      if (_levels.isNotEmpty) filters['cefr_levels'] = _levels.toList();
      if (_minStreak.text.isNotEmpty) {
        filters['min_streak'] = int.parse(_minStreak.text);
      }
      if (_inactiveDays.text.isNotEmpty) {
        filters['inactive_days'] = int.parse(_inactiveDays.text);
      }
    }
    final config = <String, dynamic>{
      'audience': {'type': _segment ? 'segment' : 'all', 'filters': filters},
      'content': {
        'title': _title.text.trim(),
        'body': _body.text.trim(),
        'notification_type': _type.text.trim(),
        'deep_link': _link.text.trim().isEmpty ? null : _link.text.trim(),
        'use_ai_copy': _ai,
      },
      if (_sendAt != null &&
          _jobType == NotificationCampaignJobType.scheduledPush)
        'send_at': _sendAt!.toUtc().toIso8601String(),
    };
    Navigator.pop(context, {'job_type': _jobType.value, 'config': config});
  }

  Widget _chips(String labelKey, List<String> values, Set<String> selected) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(labelKey.tr(), style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final v in values)
                FilterChip(
                  label: Text(v),
                  selected: selected.contains(v),
                  onSelected: (_) => _toggle(selected, v),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
        ],
      );

  @override
  Widget build(BuildContext context) => GrowthFormSheet(
    title: 'adminGrowth.campaign.create'.tr(),
    onSave: _submit,
    children: [
      Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: DropdownButtonFormField<NotificationCampaignJobType>(
          initialValue: _jobType,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: 'adminGrowth.campaign.jobType'.tr(),
          ),
          items: [
            for (final v in NotificationCampaignJobType.values)
              DropdownMenuItem(value: v, child: Text(_typeLabel(v))),
          ],
          onChanged: (v) => setState(() => _jobType = v ?? _jobType),
        ),
      ),
      GrowthField(
        controller: _title,
        label: 'adminGrowth.campaign.fieldTitle'.tr(),
        errorText: _req(_title),
      ),
      GrowthField(
        controller: _body,
        label: 'adminGrowth.campaign.fieldBody'.tr(),
        lines: 3,
        errorText: _req(_body),
      ),
      GrowthField(
        controller: _type,
        label: 'adminGrowth.campaign.fieldType'.tr(),
      ),
      GrowthField(
        controller: _link,
        label: 'adminGrowth.campaign.fieldLink'.tr(),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('adminGrowth.campaign.useAi'.tr()),
        value: _ai,
        onChanged: (v) => setState(() => _ai = v),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('adminGrowth.campaign.segment'.tr()),
        value: _segment,
        onChanged: (v) => setState(() => _segment = v),
      ),
      if (_segment) ...[
        _chips('adminGrowth.campaign.leagues', leagues, _leagues),
        _chips('adminGrowth.campaign.levels', levels, _levels),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: GrowthField(
                controller: _minStreak,
                label: 'adminGrowth.campaign.minStreak'.tr(),
                number: true,
                errorText: _num(_minStreak),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GrowthField(
                controller: _inactiveDays,
                label: 'adminGrowth.campaign.inactiveDays'.tr(),
                number: true,
                errorText: _num(_inactiveDays),
              ),
            ),
          ],
        ),
      ],
      if (_jobType == NotificationCampaignJobType.scheduledPush)
        ListTile(
          contentPadding: EdgeInsets.zero,
          minVerticalPadding: AppSpacing.md,
          leading: const Icon(Icons.schedule),
          title: Text(
            _sendAt == null
                ? 'adminGrowth.campaign.chooseTime'.tr()
                : _sendAt.toString(),
          ),
          onTap: _pickSchedule,
        ),
    ],
  );
}
