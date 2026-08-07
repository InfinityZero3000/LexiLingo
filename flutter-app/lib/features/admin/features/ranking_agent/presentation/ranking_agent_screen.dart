import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/ranking_agent_repository.dart';

class RankingAgentScreen extends StatefulWidget {
  const RankingAgentScreen({super.key});

  @override
  State<RankingAgentScreen> createState() => _RankingAgentScreenState();
}

class _RankingAgentScreenState extends State<RankingAgentScreen> {
  final _repo = RankingAgentRepository();
  List<RankingAgentJob> _jobs = [];
  bool _loading = true;
  String? _error;

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
    } catch (_) {
      if (mounted) setState(() => _error = 'Không thể tải danh sách jobs.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.surface,
      builder: (_) => const _CreateJobSheet(),
    );
    if (payload == null) return;
    try {
      await _repo.createJob(payload);
      await _load();
    } catch (_) {
      _message('Không thể tạo job.', error: true);
    }
  }

  Future<void> _preview(RankingAgentJob job) async {
    try {
      final preview = await _repo.getPreview(job.id);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (_) => _PreviewDialog(job: job, preview: preview),
      );
    } catch (_) {
      _message('Preview chưa sẵn sàng.', error: true);
    }
  }

  Future<bool> _confirm(String title, String message, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          content: Text(message, style: GoogleFonts.spaceGrotesk()),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Huỷ')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(action)),
          ],
        ),
      ) ?? false;

  Future<void> _action(RankingAgentJob job, String action) async {
    if (action == 'apply') {
      final impactful = job.jobType == 'league_reset' || job.jobType == 'xp_event';
      final ok = await _confirm(
        'Apply job vào dữ liệu thật?',
        impactful
            ? 'Hành động này sẽ ảnh hưởng trực tiếp đến người dùng thật và không thể hoàn tác an toàn.'
            : 'Job sẽ ghi thay đổi vào dữ liệu người dùng thật.',
        'Apply',
      );
      if (!ok) return;
    } else if (action == 'cancel') {
      if (!await _confirm('Huỷ job?', 'Job đang chạy sẽ bị dừng.', 'Huỷ job')) return;
    }
    try {
      if (action == 'apply') await _repo.applyJob(job.id);
      if (action == 'cancel') await _repo.cancelJob(job.id);
      if (action == 'retry') await _repo.retryJob(job.id);
      await _load();
    } catch (_) {
      _message('Không thể thực hiện hành động.', error: true);
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.spaceGrotesk()),
      backgroundColor: error ? AppColors.error : AppColors.success,
    ));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _create,
          icon: const Icon(Icons.add),
          label: Text('Tạo job', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        ),
        body: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverAppBar(
                pinned: true,
                backgroundColor: AppColors.background,
                elevation: 0,
                scrolledUnderElevation: 0,
                leading: IconButton(
                  icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
                  onPressed: AdminShell.openDrawer,
                ),
                title: Text('Ranking Agent', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded), tooltip: 'Làm mới')],
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                sliver: SliverList(delegate: SliverChildListDelegate([
                  Text('Tự động hoá league reset, XP events và phát thành tích hàng loạt.', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
                  const SizedBox(height: 20),
                  if (_loading && _jobs.isEmpty)
                    const Column(children: [AdminSkeleton(height: 120), SizedBox(height: 12), AdminSkeleton(height: 120)])
                  else if (_error != null)
                    _StateCard(icon: Icons.error_outline, message: _error!, action: _load)
                  else if (_jobs.isEmpty)
                    const _StateCard(icon: Icons.emoji_events_outlined, message: 'Chưa có job nào. Tạo job đầu tiên để bắt đầu.')
                  else
                    ..._jobs.map((job) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _JobCard(job: job, onPreview: () => _preview(job), onAction: (value) => _action(job, value)),
                    )),
                ])),
              ),
            ],
          ),
        ),
      );
}

class _JobCard extends StatelessWidget {
  final RankingAgentJob job;
  final VoidCallback onPreview;
  final ValueChanged<String> onAction;
  const _JobCard({required this.job, required this.onPreview, required this.onAction});

  @override
  Widget build(BuildContext context) {
    final icon = switch (job.jobType) {
      'league_reset' => Icons.rotate_left_rounded,
      'xp_event' => Icons.bolt_rounded,
      _ => Icons.military_tech_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outline)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 44, height: 44, decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(12)), child: Icon(icon, color: AppColors.primary)),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_typeLabel(job.jobType), style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            Text(_date(job.createdAt), style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
          ])),
          _StatusChip(status: job.status),
        ]),
        if (job.isActive) ...[
          const SizedBox(height: 14),
          LinearProgressIndicator(value: job.progressPercent / 100, color: AppColors.primary, backgroundColor: AppColors.surfaceDim),
          const SizedBox(height: 4),
          Text('${job.progress['stage'] ?? ''} • ${job.progressPercent}%', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
        ],
        if (job.warnings.isNotEmpty || job.blockingErrors.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text(job.blockingErrors.isNotEmpty ? '${job.blockingErrors.length} lỗi chặn' : '${job.warnings.length} cảnh báo', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: job.blockingErrors.isNotEmpty ? AppColors.error : AppColors.warning, fontWeight: FontWeight.w700)),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 4, children: [
          if (job.status == 'preview_ready') TextButton.icon(onPressed: onPreview, icon: const Icon(Icons.visibility_outlined), label: const Text('Preview'), style: TextButton.styleFrom(minimumSize: const Size(44, 44))),
          if (job.canApply) FilledButton(onPressed: () => onAction('apply'), child: const Text('Apply')),
          if (job.isActive && job.status != 'applying') TextButton(onPressed: () => onAction('cancel'), style: TextButton.styleFrom(minimumSize: const Size(44, 44), foregroundColor: AppColors.error), child: const Text('Huỷ')),
          if (job.status == 'failed') TextButton.icon(onPressed: () => onAction('retry'), icon: const Icon(Icons.replay_rounded), label: const Text('Retry'), style: TextButton.styleFrom(minimumSize: const Size(44, 44))),
        ]),
      ]),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});
  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'completed' => AppColors.success,
      'failed' => AppColors.error,
      'preview_ready' => AppColors.warning,
      'cancelled' => AppColors.onSurfaceMuted,
      _ => AppColors.primary,
    };
    return Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: Text(status.replaceAll('_', ' '), style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700, color: color)));
  }
}

class _CreateJobSheet extends StatefulWidget {
  const _CreateJobSheet();
  @override
  State<_CreateJobSheet> createState() => _CreateJobSheetState();
}

class _CreateJobSheetState extends State<_CreateJobSheet> {
  static const _leagues = ['bronze', 'silver', 'gold', 'platinum', 'sapphire', 'ruby', 'amethyst', 'master'];
  static const _cefr = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];
  String type = 'league_reset', target = 'all', targetLeague = 'gold', targetCefr = 'B1';
  bool ai = false;
  final week = TextEditingController(), name = TextEditingController(text: 'Weekend Boost'), multiplier = TextEditingController(text: '2'), duration = TextEditingController(text: '48'), slugs = TextEditingController(), streak = TextEditingController(), vocab = TextEditingController(), leagues = <String>{}, cefr = <String>{};

  @override
  void dispose() {
    week.dispose();
    name.dispose();
    multiplier.dispose();
    duration.dispose();
    slugs.dispose();
    streak.dispose();
    vocab.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _payload() {
    Map<String, dynamic> config;
    if (type == 'league_reset') {
      config = {if (week.text.trim().isNotEmpty) 'week_start': week.text.trim()};
    } else if (type == 'xp_event') {
      final multiplierValue = double.tryParse(multiplier.text);
      final durationValue = int.tryParse(duration.text);
      if (name.text.trim().isEmpty || multiplierValue == null || !multiplierValue.isFinite || multiplierValue < 1.1 || multiplierValue > 5 || durationValue == null || durationValue < 1 || durationValue > 168) return null;
      config = {'name': name.text.trim(), 'multiplier': multiplierValue, 'duration_hours': durationValue, 'target': target == 'league' ? 'league:$targetLeague' : target == 'cefr' ? 'cefr:$targetCefr' : 'all'};
    } else {
      final values = slugs.text.split(RegExp(r'[\s,]+')).where((value) => value.isNotEmpty).toList();
      final streakValue = streak.text.isEmpty ? null : int.tryParse(streak.text);
      final vocabValue = vocab.text.isEmpty ? null : int.tryParse(vocab.text);
      if (values.isEmpty || (streak.text.isNotEmpty && (streakValue == null || streakValue < 0)) || (vocab.text.isNotEmpty && (vocabValue == null || vocabValue < 0))) return null;
      config = {'achievement_slugs': values, 'criteria': {if (streakValue != null) 'min_streak': streakValue, if (vocabValue != null) 'min_vocabulary_mastered': vocabValue, if (leagues.isNotEmpty) 'leagues': leagues.toList(), if (cefr.isNotEmpty) 'cefr_levels': cefr.toList()}};
    }
    return {'job_type': type, 'config': config, 'use_ai_insights': ai};
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: SafeArea(child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tạo Ranking Agent job', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Loại job'), items: const [DropdownMenuItem(value: 'league_reset', child: Text('League Reset')), DropdownMenuItem(value: 'xp_event', child: Text('XP Event')), DropdownMenuItem(value: 'achievement_batch', child: Text('Achievement Batch'))], onChanged: (value) => setState(() => type = value!)),
      const SizedBox(height: 12),
      if (type == 'league_reset') TextField(controller: week, decoration: const InputDecoration(labelText: 'Tuần bắt đầu (YYYY-MM-DD, tuỳ chọn)')),
      if (type == 'xp_event') ...[
        TextField(controller: name, decoration: const InputDecoration(labelText: 'Tên event *')),
        Row(children: [Expanded(child: TextField(controller: multiplier, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Multiplier *'))), const SizedBox(width: 12), Expanded(child: TextField(controller: duration, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Số giờ *')))]),
        DropdownButtonFormField<String>(initialValue: target, decoration: const InputDecoration(labelText: 'Đối tượng'), items: const [DropdownMenuItem(value: 'all', child: Text('Tất cả')), DropdownMenuItem(value: 'league', child: Text('Theo league')), DropdownMenuItem(value: 'cefr', child: Text('Theo CEFR'))], onChanged: (value) => setState(() => target = value!)),
        if (target == 'league') DropdownButtonFormField<String>(initialValue: targetLeague, items: _leagues.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => targetLeague = value!)),
        if (target == 'cefr') DropdownButtonFormField<String>(initialValue: targetCefr, items: _cefr.map((value) => DropdownMenuItem(value: value, child: Text(value))).toList(), onChanged: (value) => setState(() => targetCefr = value!)),
      ],
      if (type == 'achievement_batch') ...[
        TextField(controller: slugs, maxLines: 2, decoration: const InputDecoration(labelText: 'Achievement slugs *', hintText: 'streak_30, vocab_master_100')),
        Row(children: [Expanded(child: TextField(controller: streak, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min streak'))), const SizedBox(width: 12), Expanded(child: TextField(controller: vocab, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Min vocab')))]),
        _Choices(label: 'Leagues', values: _leagues, selected: leagues, changed: () => setState(() {})),
        _Choices(label: 'CEFR', values: _cefr, selected: cefr, changed: () => setState(() {})),
      ],
      SwitchListTile(contentPadding: EdgeInsets.zero, value: ai, onChanged: (value) => setState(() => ai = value), title: const Text('AI Insights'), subtitle: const Text('Tạo nhận xét ngắn trong bước validating.')),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Huỷ')), const SizedBox(width: 8), FilledButton(onPressed: () { final value = _payload(); if (value == null) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Vui lòng kiểm tra các trường bắt buộc.'))); return; } Navigator.pop(context, value); }, child: const Text('Tạo job'))]),
    ]))),
  );
}

class _Choices extends StatelessWidget {
  final String label;
  final List<String> values;
  final Set<String> selected;
  final VoidCallback changed;
  const _Choices({required this.label, required this.values, required this.selected, required this.changed});
  @override
  Widget build(BuildContext context) => Padding(padding: const EdgeInsets.only(top: 12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(label), Wrap(spacing: 6, children: values.map((value) => FilterChip(label: Text(value), selected: selected.contains(value), onSelected: (_) { selected.contains(value) ? selected.remove(value) : selected.add(value); changed(); })).toList())]));
}

class _PreviewDialog extends StatelessWidget {
  final RankingAgentJob job;
  final RankingAgentPreview preview;
  const _PreviewDialog({required this.job, required this.preview});
  @override
  Widget build(BuildContext context) {
    final artifact = preview.artifact;
    final entries = switch (job.jobType) {
      'league_reset' => {'Tổng người tham gia': artifact['total_participants'] ?? 0, 'Thăng hạng': (artifact['promotions'] as List?)?.length ?? 0, 'Xuống hạng': (artifact['demotions'] as List?)?.length ?? 0, 'Tuần': artifact['week'] ?? '—'},
      'xp_event' => {'Người dùng ảnh hưởng': artifact['target_user_count'] ?? 0, 'XP tăng dự kiến': artifact['estimated_total_xp_delta'] ?? 0, 'Multiplier': artifact['multiplier'] ?? '—', 'Thời lượng': '${artifact['duration_hours'] ?? '—'}h'},
      _ => {'Người dùng ảnh hưởng': artifact['total_users_affected'] ?? 0, 'Tổng XP trao': artifact['total_xp_to_award'] ?? 0, 'Achievements': (artifact['achievements'] as List?)?.length ?? 0},
    };
    return AlertDialog(title: const Text('Preview'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      ...entries.entries.map((entry) => ListTile(contentPadding: EdgeInsets.zero, title: Text(entry.key), trailing: Text('${entry.value}', style: const TextStyle(fontWeight: FontWeight.w700)))),
      if (preview.warnings.isNotEmpty) Text('Cảnh báo:\n${preview.warnings.join('\n')}', style: const TextStyle(color: AppColors.warning)),
      if (preview.blockingErrors.isNotEmpty) Text('Lỗi chặn:\n${preview.blockingErrors.join('\n')}', style: const TextStyle(color: AppColors.error)),
    ])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Đóng'))]);
  }
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? action;
  const _StateCard({required this.icon, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(40), child: Column(children: [Icon(icon, size: 44, color: AppColors.onSurfaceMuted), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)), if (action != null) TextButton(onPressed: () => action!(), child: const Text('Thử lại'))])));
}

String _typeLabel(String value) => switch (value) {'league_reset' => 'League Reset', 'xp_event' => 'XP Event', _ => 'Achievement Batch'};
String _date(String value) { final date = DateTime.tryParse(value)?.toLocal(); return date == null ? '—' : DateFormat('dd/MM/yyyy HH:mm').format(date); }
