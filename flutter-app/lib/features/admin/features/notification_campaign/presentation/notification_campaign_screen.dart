import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/notification_campaign_repository.dart';

class NotificationCampaignScreen extends StatefulWidget {
  const NotificationCampaignScreen({super.key});

  @override
  State<NotificationCampaignScreen> createState() => _NotificationCampaignScreenState();
}

class _NotificationCampaignScreenState extends State<NotificationCampaignScreen> {
  final _repository = NotificationCampaignRepository();
  List<NotificationCampaignJob> _jobs = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final jobs = await _repository.getJobs();
      if (mounted) setState(() => _jobs = jobs);
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not load campaigns.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final payload = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (_) => const _CreateCampaignDialog(),
    );
    if (payload == null) return;
    try {
      final job = await _repository.createJob(payload);
      if (mounted) setState(() => _jobs = [job, ..._jobs]);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not create campaign.')));
    }
  }

  Future<bool> _confirm(String title, String message) async =>
      await showDialog<bool>(context: context, builder: (context) => AlertDialog(
        title: Text(title), content: Text(message), actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
        ],
      )) ?? false;

  Future<void> _action(NotificationCampaignJob job, String action) async {
    if (action != 'retry' &&
        !await _confirm(
          '${action == 'apply' ? 'Apply' : 'Cancel'} campaign?',
          action == 'apply'
              ? 'This will send the campaign to its audience.'
              : 'This will stop the campaign.',
        )) {
      return;
    }
    try {
      final updated = switch (action) {
        'apply' => await _repository.apply(job.id),
        'cancel' => await _repository.cancel(job.id),
        _ => await _repository.retry(job.id),
      };
      if (mounted) setState(() => _jobs = _jobs.map((j) => j.id == updated.id ? updated : j).toList());
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not $action this campaign.')));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      backgroundColor: AppColors.background,
      leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: AdminShell.openDrawer),
      title: Text('Notification Campaigns', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
      actions: [IconButton(onPressed: _create, tooltip: 'Create campaign', icon: const Icon(Icons.add_rounded))],
    ),
    floatingActionButton: FloatingActionButton(onPressed: _create, backgroundColor: AppColors.primaryBright, child: const Icon(Icons.add_rounded)),
    body: RefreshIndicator(onRefresh: _load, child: _body()),
  );

  Widget _body() {
    if (_loading && _jobs.isEmpty) return ListView(padding: const EdgeInsets.all(16), children: [AdminSkeleton(height: 112), const SizedBox(height: 12), AdminSkeleton(height: 112)]);
    if (_error != null && _jobs.isEmpty) return ListView(children: [SizedBox(height: 160), Icon(Icons.error_outline, size: 44, color: AppColors.error), Center(child: Text('Could not load campaigns', style: GoogleFonts.spaceGrotesk(color: AppColors.error))), Center(child: TextButton(onPressed: _load, child: const Text('Retry')))]);
    if (_jobs.isEmpty) return ListView(children: [const SizedBox(height: 160), const Icon(Icons.campaign_outlined, size: 48, color: AppColors.onSurfaceMuted), Center(child: Text('No campaigns yet', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)))]);
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), itemCount: _jobs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (_, index) => _CampaignCard(job: _jobs[index], onAction: (a) => _action(_jobs[index], a)),
    );
  }
}

class _CampaignCard extends StatelessWidget {
  final NotificationCampaignJob job;
  final ValueChanged<String> onAction;
  const _CampaignCard({required this.job, required this.onAction});

  IconData get _icon => switch (job.jobType) { 'in_app_broadcast' => Icons.message_outlined, 'scheduled_push' => Icons.schedule_outlined, _ => Icons.notifications_outlined };
  Color get _statusColor => switch (job.status) { 'completed' => AppColors.success, 'failed' => AppColors.error, 'sending' || 'preview_ready' => AppColors.warning, _ => AppColors.primary };
  String _date(String value) { final d = DateTime.tryParse(value)?.toLocal(); return d == null ? '—' : '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}'; }

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: job.needsAttention ? AppColors.primary : AppColors.outlineVariant, width: 0.5)),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(_icon, color: AppColors.primary)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(job.jobType.replaceAll('_', ' '), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          const SizedBox(height: 4),
          Text('Created ${_date(job.createdAt)}', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
          if (job.scheduledAt != null) Text('Scheduled ${_date(job.scheduledAt!)}', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
        ])),
        Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: _statusColor.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(job.status.replaceAll('_', ' '), style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: _statusColor))),
      ]),
      if (job.needsAttention) ...[const SizedBox(height: 12), LinearProgressIndicator(value: job.progressPercent / 100, color: AppColors.primary)],
      if (job.errorMessage != null) ...[const SizedBox(height: 8), Text(job.errorMessage!, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.error))],
      if (job.canApply || job.canCancel || job.canRetry) ...[const SizedBox(height: 8), Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        if (job.canRetry) TextButton(onPressed: () => onAction('retry'), child: const Text('Retry')),
        if (job.canCancel) TextButton(onPressed: () => onAction('cancel'), child: const Text('Cancel')),
        if (job.canApply) FilledButton(onPressed: () => onAction('apply'), child: const Text('Apply')),
      ])],
    ]),
  );
}

class _CreateCampaignDialog extends StatefulWidget {
  const _CreateCampaignDialog();
  @override State<_CreateCampaignDialog> createState() => _CreateCampaignDialogState();
}

class _CreateCampaignDialogState extends State<_CreateCampaignDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController(), _body = TextEditingController(), _type = TextEditingController(text: 'campaign'), _link = TextEditingController(), _minStreak = TextEditingController(), _inactiveDays = TextEditingController();
  NotificationCampaignJobType _jobType = NotificationCampaignJobType.targetedPush;
  bool _segment = false, _ai = false;
  DateTime? _sendAt;
  final Set<String> _leagues = {}, _levels = {};
  static const leagues = ['bronze', 'silver', 'gold', 'platinum', 'sapphire', 'ruby', 'amethyst', 'master'];
  static const levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override void dispose() { for (final c in [_title, _body, _type, _link, _minStreak, _inactiveDays]) { c.dispose(); } super.dispose(); }
  InputDecoration _decoration(String label) => InputDecoration(labelText: label, border: const OutlineInputBorder());
  void _toggle(Set<String> values, String value) => setState(() => values.contains(value) ? values.remove(value) : values.add(value));

  Future<void> _pickSchedule() async {
    final date = await showDatePicker(context: context, firstDate: DateTime.now(), lastDate: DateTime.now().add(const Duration(days: 365)), initialDate: _sendAt ?? DateTime.now());
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_sendAt ?? DateTime.now()));
    if (time != null) setState(() => _sendAt = DateTime(date.year, date.month, date.day, time.hour, time.minute));
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_jobType == NotificationCampaignJobType.scheduledPush && _sendAt == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a schedule time.'))); return; }
    final filters = <String, dynamic>{'has_fcm_token': true};
    if (_segment) {
      if (_leagues.isNotEmpty) filters['leagues'] = _leagues.toList();
      if (_levels.isNotEmpty) filters['cefr_levels'] = _levels.toList();
      if (_minStreak.text.isNotEmpty) filters['min_streak'] = int.parse(_minStreak.text);
      if (_inactiveDays.text.isNotEmpty) filters['inactive_days'] = int.parse(_inactiveDays.text);
    }
    final config = <String, dynamic>{
      'audience': {'type': _segment ? 'segment' : 'all', 'filters': filters},
      'content': {'title': _title.text.trim(), 'body': _body.text.trim(), 'notification_type': _type.text.trim(), 'deep_link': _link.text.trim().isEmpty ? null : _link.text.trim(), 'use_ai_copy': _ai},
      if (_sendAt != null && _jobType == NotificationCampaignJobType.scheduledPush) 'send_at': _sendAt!.toUtc().toIso8601String(),
    };
    Navigator.pop(context, {'job_type': _jobType.value, 'config': config});
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Create campaign', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
    content: SizedBox(width: 520, child: Form(key: _formKey, child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      DropdownButtonFormField(initialValue: _jobType, decoration: _decoration('Job type'), items: NotificationCampaignJobType.values.map((v) => DropdownMenuItem(value: v, child: Text(v.label))).toList(), onChanged: (v) => setState(() => _jobType = v!)),
      const SizedBox(height: 12),
      TextFormField(controller: _title, maxLength: 100, decoration: _decoration('Title'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      TextFormField(controller: _body, maxLength: 300, maxLines: 3, decoration: _decoration('Body'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
      TextFormField(controller: _type, decoration: _decoration('Notification type')),
      const SizedBox(height: 12), TextFormField(controller: _link, decoration: _decoration('Deep link (optional)')),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Improve copy with AI'), value: _ai, onChanged: (v) => setState(() => _ai = v)),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Target a segment'), value: _segment, onChanged: (v) => setState(() => _segment = v)),
      if (_segment) ...[
        Align(alignment: Alignment.centerLeft, child: Text('Leagues', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))),
        Wrap(spacing: 6, children: leagues.map((v) => FilterChip(label: Text(v), selected: _leagues.contains(v), onSelected: (_) => _toggle(_leagues, v))).toList()),
        Align(alignment: Alignment.centerLeft, child: Text('CEFR levels', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))),
        Wrap(spacing: 6, children: levels.map((v) => FilterChip(label: Text(v), selected: _levels.contains(v), onSelected: (_) => _toggle(_levels, v))).toList()),
        Row(children: [Expanded(child: TextFormField(controller: _minStreak, keyboardType: TextInputType.number, decoration: _decoration('Min streak'), validator: (v) => v!.isEmpty || int.tryParse(v) != null ? null : 'Number required')), const SizedBox(width: 8), Expanded(child: TextFormField(controller: _inactiveDays, keyboardType: TextInputType.number, decoration: _decoration('Inactive days'), validator: (v) => v!.isEmpty || int.tryParse(v) != null ? null : 'Number required'))]),
      ],
      if (_jobType == NotificationCampaignJobType.scheduledPush) ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.schedule), title: Text(_sendAt == null ? 'Choose schedule time' : _sendAt.toString()), onTap: _pickSchedule),
    ])))),
    actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: _submit, child: const Text('Create'))],
  );
}
