import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../data/content_qa_repository.dart';

class ContentQaScreen extends StatefulWidget {
  const ContentQaScreen({super.key});

  @override
  State<ContentQaScreen> createState() => _ContentQaScreenState();
}

class _ContentQaScreenState extends State<ContentQaScreen> {
  final _repository = ContentQaRepository();
  ContentQaQueue? _queue;
  String _filter = 'preview_ready';
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
      final queue = await _repository.getQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load the content QA queue.';
        _loading = false;
      });
    }
  }

  List<ContentQaJob> get _jobs => switch (_filter) {
        'failed' => _queue?.failed ?? [],
        'completed' => _queue?.applied ?? [],
        _ => _queue?.reviewable ?? [],
      };

  Future<void> _openJob(ContentQaJob job) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.background,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _JobDetailSheet(job: job, repository: _repository),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
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
              title: Text(
                'Content QA Queue',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'Review generated content',
                    style: GoogleFonts.spaceGrotesk(fontSize: 27, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${_queue?.total ?? 0} tracked jobs',
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceMuted),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const _QueueSkeleton()
                  else if (_error != null)
                    _MessageCard(
                      icon: Icons.error_outline_rounded,
                      message: _error!,
                      actionLabel: 'Try again',
                      onAction: _load,
                    )
                  else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _QueueFilter(label: 'Needs approval', count: _queue!.reviewable.length, value: 'preview_ready', selected: _filter, onSelected: _selectFilter),
                          const SizedBox(width: 8),
                          _QueueFilter(label: 'Needs repair', count: _queue!.failed.length, value: 'failed', selected: _filter, onSelected: _selectFilter),
                          const SizedBox(width: 8),
                          _QueueFilter(label: 'Published', count: _queue!.applied.length, value: 'completed', selected: _filter, onSelected: _selectFilter),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    if (_jobs.isEmpty)
                      const _MessageCard(icon: Icons.fact_check_outlined, message: 'Nothing is waiting in this bucket.')
                    else
                      ..._jobs.indexed.map(
                        (entry) => StaggeredEntrance(
                          index: entry.$1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _JobCard(job: entry.$2, onTap: () => _openJob(entry.$2)),
                          ),
                        ),
                      ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _selectFilter(String value) => setState(() => _filter = value);
}

class _QueueFilter extends StatelessWidget {
  final String label;
  final int count;
  final String value;
  final String selected;
  final ValueChanged<String> onSelected;

  const _QueueFilter({required this.label, required this.count, required this.value, required this.selected, required this.onSelected});

  @override
  Widget build(BuildContext context) => FilterChip(
        selected: value == selected,
        onSelected: (_) => onSelected(value),
        label: Text('$label  $count', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
        selectedColor: AppColors.primaryContainer,
        checkmarkColor: AppColors.primary,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.outlineVariant),
        materialTapTargetSize: MaterialTapTargetSize.padded,
      );
}

class _JobCard extends StatelessWidget {
  final ContentQaJob job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 88),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.outlineVariant, width: 0.5),
            ),
            child: Row(
              children: [
                _StatusIcon(status: job.status),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(job.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      const SizedBox(height: 5),
                      Text(
                        '${job.id.length > 8 ? job.id.substring(0, 8) : job.id} · ${job.updatedAt == null ? 'Unknown date' : DateFormat.yMMMd().add_jm().format(job.updatedAt!.toLocal())}',
                        style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.chevron_right_rounded, color: AppColors.onSurfaceMuted),
              ],
            ),
          ),
        ),
      );
}

class _StatusIcon extends StatelessWidget {
  final String status;
  const _StatusIcon({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, background, icon) = switch (status) {
      'preview_ready' => (AppColors.warning, AppColors.warningContainer, Icons.rate_review_outlined),
      'failed' => (AppColors.error, AppColors.errorContainer, Icons.error_outline_rounded),
      _ => (AppColors.success, AppColors.successContainer, Icons.check_circle_outline_rounded),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(12)),
      child: Icon(icon, color: color),
    );
  }
}

class _JobDetailSheet extends StatefulWidget {
  final ContentQaJob job;
  final ContentQaRepository repository;
  const _JobDetailSheet({required this.job, required this.repository});

  @override
  State<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<_JobDetailSheet> {
  ContentQaJob? _job;
  ContentQaPreview? _preview;
  bool _loading = true;
  bool _acting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([widget.repository.getJob(widget.job.id), widget.repository.getPreview(widget.job.id)]);
      if (!mounted) return;
      setState(() {
        _job = results[0] as ContentQaJob;
        _preview = results[1] as ContentQaPreview;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not load this job preview.';
        _loading = false;
      });
    }
  }

  Future<void> _action(String action) async {
    if (action == 'apply' || action == 'cancel') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(action == 'apply' ? 'Approve & publish?' : 'Reject this job?'),
          content: Text(action == 'apply'
              ? 'This will publish the generated content to production immediately.'
              : 'This will discard the generated content for this job.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Confirm')),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _acting = true);
    try {
      if (action == 'apply') await widget.repository.apply(widget.job.id);
      if (action == 'retry') await widget.repository.retry(widget.job.id);
      if (action == 'cancel') await widget.repository.cancel(widget.job.id);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _acting = false;
        _error = 'Could not $action this job.';
      });
    }
  }

  Future<void> _edit(ContentQaLesson lesson, ContentQaExercise exercise) async {
    final updated = await showModalBottomSheet<ContentQaPreview>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppColors.surface,
      builder: (_) => _EditExerciseSheet(repository: widget.repository, jobId: widget.job.id, lesson: lesson, exercise: exercise),
    );
    if (updated != null && mounted) setState(() => _preview = updated);
  }

  @override
  Widget build(BuildContext context) {
    final job = _job ?? widget.job;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.92,
      minChildSize: 0.6,
      maxChildSize: 0.96,
      builder: (_, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outlineVariant, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Text(job.title, style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface))),
              IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close_rounded), tooltip: 'Close'),
            ],
          ),
          Text(job.id, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 18),
          if (_loading)
            const SectionCardSkeleton(contentHeight: 240)
          else if (_error != null && _preview == null)
            _MessageCard(icon: Icons.error_outline_rounded, message: _error!, actionLabel: 'Try again', onAction: _load)
          else ...[
            _Summary(preview: _preview!),
            const SizedBox(height: 16),
            _Validation(job: job, preview: _preview!),
            const SizedBox(height: 16),
            Text('Lessons & exercises', style: GoogleFonts.spaceGrotesk(fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 8),
            if (_preview!.lessons.isEmpty)
              const _MessageCard(icon: Icons.menu_book_outlined, message: 'No lesson content in this preview.')
            else
              ..._preview!.lessons.map((lesson) => _LessonCard(lesson: lesson, editable: job.status == 'preview_ready', onEdit: (exercise) => _edit(lesson, exercise))),
            if (_error != null) ...[
              const SizedBox(height: 12),
              _MessageCard(icon: Icons.error_outline_rounded, message: _error!),
            ],
            const SizedBox(height: 20),
            _Actions(status: job.status, busy: _acting, onAction: _action),
          ],
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final ContentQaPreview preview;
  const _Summary({required this.preview});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _Metric(label: 'Courses', value: preview.courseCount),
          _Metric(label: 'Lessons', value: preview.lessons.length),
          _Metric(label: 'Vocabulary', value: preview.vocabularyCount),
          _Metric(label: 'Exercises', value: preview.exerciseCount),
        ],
      );
}

class _Metric extends StatelessWidget {
  final String label;
  final int value;
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Container(
        width: (MediaQuery.sizeOf(context).width - 48) / 2,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outlineVariant, width: 0.5)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$value', style: GoogleFonts.spaceGrotesk(fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
        ]),
      );
}

class _Validation extends StatelessWidget {
  final ContentQaJob job;
  final ContentQaPreview preview;
  const _Validation({required this.job, required this.preview});

  @override
  Widget build(BuildContext context) {
    final errors = [...job.blockingErrors, ...preview.blockingErrors];
    final warnings = [...job.warnings, ...preview.warnings];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: AppColors.outlineVariant, width: 0.5)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Validation', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        const SizedBox(height: 8),
        if (errors.isEmpty && warnings.isEmpty)
          Text('✓ No blocking issues', style: GoogleFonts.spaceGrotesk(color: AppColors.success, fontWeight: FontWeight.w600))
        else ...[
          ...errors.map((message) => _Issue(message: message, error: true)),
          ...warnings.map((message) => _Issue(message: message, error: false)),
        ],
      ]),
    );
  }
}

class _Issue extends StatelessWidget {
  final String message;
  final bool error;
  const _Issue({required this.message, required this.error});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text('• $message', style: GoogleFonts.spaceGrotesk(fontSize: 13, color: error ? AppColors.error : AppColors.warning)),
      );
}

class _LessonCard extends StatelessWidget {
  final ContentQaLesson lesson;
  final bool editable;
  final ValueChanged<ContentQaExercise> onEdit;
  const _LessonCard({required this.lesson, required this.editable, required this.onEdit});

  @override
  Widget build(BuildContext context) => Card(
        color: AppColors.surface,
        elevation: 0,
        margin: const EdgeInsets.only(bottom: 10),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: AppColors.outlineVariant, width: 0.5)),
        child: ExpansionTile(
          title: Text(lesson.title, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          subtitle: lesson.outcome == null ? null : Text(lesson.outcome!, maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
          children: lesson.exercises.map((exercise) => ListTile(
            contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
            title: Text(exercise.question, style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurface)),
            subtitle: Text([exercise.uiType, if (exercise.phase != null) exercise.phase!].join(' · '), style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
            trailing: IconButton(
              onPressed: editable ? () => onEdit(exercise) : null,
              icon: const Icon(Icons.edit_outlined),
              tooltip: 'Edit exercise',
            ),
          )).toList(),
        ),
      );
}

class _Actions extends StatelessWidget {
  final String status;
  final bool busy;
  final ValueChanged<String> onAction;
  const _Actions({required this.status, required this.busy, required this.onAction});

  @override
  Widget build(BuildContext context) => Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          if (status == 'preview_ready')
            FilledButton.icon(onPressed: busy ? null : () => onAction('apply'), icon: const Icon(Icons.check_circle_outline), label: const Text('Approve & publish')),
          if (status == 'preview_ready' || status == 'failed')
            OutlinedButton.icon(onPressed: busy ? null : () => onAction('cancel'), icon: const Icon(Icons.cancel_outlined), label: const Text('Reject')),
          if (status == 'failed')
            OutlinedButton.icon(onPressed: busy ? null : () => onAction('retry'), icon: const Icon(Icons.replay_rounded), label: const Text('Retry')),
          if (busy) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary)),
        ],
      );
}

class _EditExerciseSheet extends StatefulWidget {
  final ContentQaRepository repository;
  final String jobId;
  final ContentQaLesson lesson;
  final ContentQaExercise exercise;
  const _EditExerciseSheet({required this.repository, required this.jobId, required this.lesson, required this.exercise});

  @override
  State<_EditExerciseSheet> createState() => _EditExerciseSheetState();
}

class _EditExerciseSheetState extends State<_EditExerciseSheet> {
  late final TextEditingController _question = TextEditingController(text: widget.exercise.question);
  late final TextEditingController _answer = TextEditingController(text: widget.exercise.correctAnswer);
  late final TextEditingController _explanation = TextEditingController(text: widget.exercise.explanation ?? '');
  late final TextEditingController _options = TextEditingController(text: widget.exercise.options == null ? '' : const JsonEncoder.withIndent('  ').convert(widget.exercise.options));
  late final TextEditingController _outcome = TextEditingController(text: widget.lesson.outcome ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _explanation.dispose();
    _options.dispose();
    _outcome.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    dynamic options;
    try {
      if (_options.text.trim().isNotEmpty) options = jsonDecode(_options.text);
    } on FormatException {
      setState(() => _error = 'Options must be valid JSON.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final preview = await widget.repository.updateRecord(widget.jobId, widget.exercise.id, {
        'question': _question.text,
        'correct_answer': _answer.text,
        if (_explanation.text.isNotEmpty) 'explanation': _explanation.text,
        if (options != null) 'options': options,
        if (_outcome.text.isNotEmpty) 'lesson_outcome': _outcome.text,
      });
      if (mounted) Navigator.pop(context, preview);
    } catch (_) {
      if (mounted) setState(() { _saving = false; _error = 'Could not save this edit.'; });
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 20, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
        child: SingleChildScrollView(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Edit exercise', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            Text(widget.lesson.title, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
            const SizedBox(height: 16),
            _Field(controller: _question, label: 'Question', lines: 2),
            _Field(controller: _options, label: 'Options (JSON, optional)', lines: 3),
            _Field(controller: _answer, label: 'Correct answer'),
            _Field(controller: _explanation, label: 'Explanation (optional)', lines: 2),
            _Field(controller: _outcome, label: 'Lesson outcome', lines: 2),
            if (_error != null) Text(_error!, style: GoogleFonts.spaceGrotesk(color: AppColors.error)),
            const SizedBox(height: 12),
            FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          ]),
        ),
      );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int lines;
  const _Field({required this.controller, required this.label, this.lines = 1});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          maxLines: lines,
          style: GoogleFonts.spaceGrotesk(color: AppColors.onSurface),
          decoration: InputDecoration(labelText: label, alignLabelWithHint: lines > 1),
        ),
      );
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;
  const _MessageCard({required this.icon, required this.message, this.actionLabel, this.onAction});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outlineVariant, width: 0.5)),
        child: Column(children: [
          Icon(icon, size: 32, color: AppColors.onSurfaceMuted),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
          if (onAction != null) TextButton(onPressed: onAction, child: Text(actionLabel ?? 'Retry')),
        ]),
      );
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) => const Column(children: [
        AdminSkeleton(height: 44, borderRadius: 22),
        SizedBox(height: 16),
        ListRowSkeleton(),
        ListRowSkeleton(),
        ListRowSkeleton(),
      ]);
}
