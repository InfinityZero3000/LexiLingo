import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/growth_tone.dart';
import '../../../shared/widgets/admin_error_view.dart';
import '../../../shared/widgets/growth_job_actions.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/widgets/stagger_list.dart';
import '../data/content_qa_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class ContentQaScreen extends StatefulWidget {
  const ContentQaScreen({super.key, this.repository});

  final ContentQaRepository? repository;

  @override
  State<ContentQaScreen> createState() => _ContentQaScreenState();
}

class _ContentQaScreenState extends State<ContentQaScreen> {
  late final ContentQaRepository _repository =
      widget.repository ?? ContentQaRepository();
  ContentQaQueue? _queue;
  String _filter = 'preview_ready';
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
      final queue = await _repository.getQueue();
      if (!mounted) return;
      setState(() {
        _queue = queue;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
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
      backgroundColor: context.toneCanvas,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      builder: (_) => _JobDetailSheet(
        job: job,
        repository: _repository,
        canAct: context.read<AdminPermissions>().can('content_agent:create'),
        canEdit: context.read<AdminPermissions>().can('content_agent:update'),
      ),
    );
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.toneCanvas,
      body: RefreshIndicator(
        color: context.toneAccent,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: context.toneCanvas,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: Icon(Icons.menu_rounded, color: context.toneText),
                onPressed: AdminShell.openDrawer,
              ),
              title: Text(
                'adminGrowth.qa.title'.tr(),
                style: context.adminStyle(
                  fontWeight: FontWeight.w700,
                  color: context.toneText,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'adminGrowth.qa.headline'.tr(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.toneText,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'adminGrowth.qa.tracked'.tr(
                      args: ['${_queue?.total ?? 0}'],
                    ),
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
                  ),
                  const SizedBox(height: 20),
                  if (_loading)
                    const _QueueSkeleton()
                  else if (_error != null)
                    SizedBox(
                      height: 360,
                      child: AdminErrorView(error: _error!, onRetry: _load),
                    )
                  else ...[
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _QueueFilter(
                            label: 'adminGrowth.qa.tabNeeds'.tr(),
                            count: _queue!.reviewable.length,
                            value: 'preview_ready',
                            selected: _filter,
                            onSelected: _selectFilter,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _QueueFilter(
                            label: 'adminGrowth.qa.tabRepair'.tr(),
                            count: _queue!.failed.length,
                            value: 'failed',
                            selected: _filter,
                            onSelected: _selectFilter,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          _QueueFilter(
                            label: 'adminGrowth.qa.tabPublished'.tr(),
                            count: _queue!.applied.length,
                            value: 'completed',
                            selected: _filter,
                            onSelected: _selectFilter,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    if (_jobs.isEmpty)
                      _MessageCard(
                        icon: Icons.fact_check_outlined,
                        message: 'adminGrowth.qa.emptyBucket'.tr(),
                      )
                    else
                      ..._jobs.indexed.map(
                        (entry) => StaggeredEntrance(
                          index: entry.$1,
                          child: Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _JobCard(
                              job: entry.$2,
                              onTap: () => _openJob(entry.$2),
                            ),
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

  const _QueueFilter({
    required this.label,
    required this.count,
    required this.value,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) => FilterChip(
    selected: value == selected,
    onSelected: (_) => onSelected(value),
    label: Text(
      '$label  $count',
      style: context.adminStyle(fontWeight: FontWeight.w600),
    ),
    selectedColor: context.toneAccentBg,
    checkmarkColor: context.toneAccent,
    backgroundColor: context.toneCard,
    side: BorderSide(color: context.toneLine),
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}

class _JobCard extends StatelessWidget {
  final ContentQaJob job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: context.toneCard,
    borderRadius: BorderRadius.circular(AppRadius.lg),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        constraints: const BoxConstraints(minHeight: 88),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: context.toneLine, width: 0.5),
        ),
        child: Row(
          children: [
            _StatusIcon(status: job.status),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    job.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: context.adminStyle(
                      fontWeight: FontWeight.w700,
                      color: context.toneText,
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    '${job.id.length > 8 ? job.id.substring(0, 8) : job.id} · ${job.updatedAt == null ? 'adminGrowth.qa.unknownDate'.tr() : intl.DateFormat.yMMMd().add_jm().format(job.updatedAt!.toLocal())}',
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Icon(Icons.chevron_right_rounded, color: context.toneMuted),
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
      'preview_ready' => (
        context.toneWarning,
        context.toneWarningBg,
        Icons.rate_review_outlined,
      ),
      'failed' => (
        context.toneDanger,
        context.toneDangerBg,
        Icons.error_outline_rounded,
      ),
      _ => (
        context.toneSuccess,
        context.toneSuccessBg,
        Icons.check_circle_outline_rounded,
      ),
    };
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Icon(icon, color: color),
    );
  }
}

class _JobDetailSheet extends StatefulWidget {
  final ContentQaJob job;
  final ContentQaRepository repository;
  final bool canAct;
  final bool canEdit;
  const _JobDetailSheet({
    required this.job,
    required this.repository,
    this.canAct = true,
    this.canEdit = true,
  });

  @override
  State<_JobDetailSheet> createState() => _JobDetailSheetState();
}

class _JobDetailSheetState extends State<_JobDetailSheet> {
  ContentQaJob? _job;
  ContentQaPreview? _preview;
  bool _loading = true;
  bool _acting = false;
  String? _error;
  Object? _loadError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.repository.getJob(widget.job.id),
        widget.repository.getPreview(widget.job.id),
      ]);
      if (!mounted) return;
      setState(() {
        _job = results[0] as ContentQaJob;
        _preview = results[1] as ContentQaPreview;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadError = e;
        _loading = false;
      });
    }
  }

  Future<void> _action(String action) async {
    if (action == 'apply') {
      final ok = await confirmApply(
        context,
        title: 'adminGrowth.qa.approveTitle'.tr(),
        body: 'adminGrowth.qa.approveBody'.tr(),
      );
      if (!ok || !mounted) return;
    } else if (action == 'cancel') {
      final ok = await confirmCancel(
        context,
        title: 'adminGrowth.qa.rejectTitle'.tr(),
        body: 'adminGrowth.qa.rejectBody'.tr(),
      );
      if (!ok || !mounted) return;
    }
    setState(() => _acting = true);
    try {
      if (action == 'apply') await widget.repository.apply(widget.job.id);
      if (action == 'retry') await widget.repository.retry(widget.job.id);
      if (action == 'cancel') await widget.repository.cancel(widget.job.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final api = AdminApiError.from(e);
      setState(() {
        _acting = false;
        _error = api.isForbidden || api.isFeatureOff
            ? api.message.resolve()
            : 'adminGrowth.qa.actionFailed'.tr(
                args: ['adminGrowth.jobs.$action'.tr().toLowerCase()],
              );
      });
    }
  }

  Future<void> _edit(ContentQaLesson lesson, ContentQaExercise exercise) async {
    final updated = await showModalBottomSheet<ContentQaPreview>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: context.toneCard,
      builder: (_) => _EditExerciseSheet(
        repository: widget.repository,
        jobId: widget.job.id,
        lesson: lesson,
        exercise: exercise,
      ),
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
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.toneLine,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  job.title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.toneText,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
                tooltip: 'adminGrowth.qa.close'.tr(),
              ),
            ],
          ),
          Text(
            job.id,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
          ),
          const SizedBox(height: 18),
          if (_loading)
            const SectionCardSkeleton(contentHeight: 240)
          else if (_loadError != null && _preview == null)
            SizedBox(
              height: 320,
              child: AdminErrorView(
                error: _loadError!,
                onRetry: () {
                  setState(() {
                    _loading = true;
                    _loadError = null;
                  });
                  _load();
                },
              ),
            )
          else ...[
            _Summary(preview: _preview!),
            const SizedBox(height: AppSpacing.lg),
            _Validation(job: job, preview: _preview!),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'adminGrowth.qa.lessonsExercises'.tr(),
              style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.toneText,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            if (_preview!.lessons.isEmpty)
              _MessageCard(
                icon: Icons.menu_book_outlined,
                message: 'adminGrowth.qa.noLessons'.tr(),
              )
            else
              ..._preview!.lessons.map(
                (lesson) => _LessonCard(
                  lesson: lesson,
                  editable: widget.canEdit && job.status == 'preview_ready',
                  onEdit: (exercise) => _edit(lesson, exercise),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              _MessageCard(icon: Icons.error_outline_rounded, message: _error!),
            ],
            const SizedBox(height: 20),
            if (widget.canAct)
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
      _Metric(label: 'adminGrowth.qa.courses'.tr(), value: preview.courseCount),
      _Metric(
        label: 'adminGrowth.qa.lessons'.tr(),
        value: preview.lessons.length,
      ),
      _Metric(
        label: 'adminGrowth.qa.vocabulary'.tr(),
        value: preview.vocabularyCount,
      ),
      _Metric(
        label: 'adminGrowth.qa.exercises'.tr(),
        value: preview.exerciseCount,
      ),
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
    decoration: BoxDecoration(
      color: context.toneCard,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: context.toneLine, width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$value',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: context.toneText,
          ),
        ),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
        ),
      ],
    ),
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
      decoration: BoxDecoration(
        color: context.toneCard,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: context.toneLine, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'adminGrowth.qa.validation'.tr(),
            style: context.adminStyle(
              fontWeight: FontWeight.w700,
              color: context.toneText,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (errors.isEmpty && warnings.isEmpty)
            Text(
              'adminGrowth.qa.noIssues'.tr(),
              style: context.adminStyle(
                color: context.toneSuccess,
                fontWeight: FontWeight.w600,
              ),
            )
          else ...[
            ...errors.map((message) => _Issue(message: message, error: true)),
            ...warnings.map(
              (message) => _Issue(message: message, error: false),
            ),
          ],
        ],
      ),
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
    child: Text(
      '• $message',
      style: Theme.of(context).textTheme.bodySmall?.copyWith(
        color: error ? context.toneDanger : context.toneWarning,
      ),
    ),
  );
}

class _LessonCard extends StatelessWidget {
  final ContentQaLesson lesson;
  final bool editable;
  final ValueChanged<ContentQaExercise> onEdit;
  const _LessonCard({
    required this.lesson,
    required this.editable,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) => Card(
    color: context.toneCard,
    elevation: 0,
    margin: const EdgeInsets.only(bottom: 10),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      side: BorderSide(color: context.toneLine, width: 0.5),
    ),
    child: ExpansionTile(
      title: Text(
        lesson.title,
        style: context.adminStyle(
          fontWeight: FontWeight.w700,
          color: context.toneText,
        ),
      ),
      subtitle: lesson.outcome == null
          ? null
          : Text(
              lesson.outcome!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
            ),
      children: lesson.exercises
          .map(
            (exercise) => ListTile(
              contentPadding: const EdgeInsets.fromLTRB(16, 4, 8, 4),
              title: Text(
                exercise.question,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: context.toneText),
              ),
              subtitle: Text(
                [
                  exercise.uiType,
                  if (exercise.phase != null) exercise.phase!,
                ].join(' · '),
                style: Theme.of(
                  context,
                ).textTheme.labelSmall?.copyWith(color: context.toneMuted),
              ),
              trailing: IconButton(
                onPressed: editable ? () => onEdit(exercise) : null,
                icon: const Icon(Icons.edit_outlined),
                tooltip: 'adminGrowth.qa.editExercise'.tr(),
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _Actions extends StatelessWidget {
  final String status;
  final bool busy;
  final ValueChanged<String> onAction;
  const _Actions({
    required this.status,
    required this.busy,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 10,
    runSpacing: 10,
    children: [
      if (status == 'preview_ready')
        FilledButton.icon(
          onPressed: busy ? null : () => onAction('apply'),
          icon: const Icon(Icons.check_circle_outline),
          label: Text('adminGrowth.qa.approvePublish'.tr()),
        ),
      if (status == 'preview_ready' || status == 'failed')
        OutlinedButton.icon(
          onPressed: busy ? null : () => onAction('cancel'),
          icon: const Icon(Icons.cancel_outlined),
          label: Text('adminGrowth.qa.reject'.tr()),
        ),
      if (status == 'failed')
        OutlinedButton.icon(
          onPressed: busy ? null : () => onAction('retry'),
          icon: const Icon(Icons.replay_rounded),
          label: Text('adminGrowth.jobs.retry'.tr()),
        ),
      if (busy)
        SizedBox(
          width: AppSpacing.xl,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: context.toneAccent,
          ),
        ),
    ],
  );
}

class _EditExerciseSheet extends StatefulWidget {
  final ContentQaRepository repository;
  final String jobId;
  final ContentQaLesson lesson;
  final ContentQaExercise exercise;
  const _EditExerciseSheet({
    required this.repository,
    required this.jobId,
    required this.lesson,
    required this.exercise,
  });

  @override
  State<_EditExerciseSheet> createState() => _EditExerciseSheetState();
}

class _EditExerciseSheetState extends State<_EditExerciseSheet> {
  late final TextEditingController _question = TextEditingController(
    text: widget.exercise.question,
  );
  late final TextEditingController _answer = TextEditingController(
    text: widget.exercise.correctAnswer,
  );
  late final TextEditingController _explanation = TextEditingController(
    text: widget.exercise.explanation ?? '',
  );
  late final TextEditingController _options = TextEditingController(
    text: widget.exercise.options == null
        ? ''
        : const JsonEncoder.withIndent('  ').convert(widget.exercise.options),
  );
  late final TextEditingController _outcome = TextEditingController(
    text: widget.lesson.outcome ?? '',
  );
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
      setState(() => _error = 'adminGrowth.qa.optionsInvalid'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final preview = await widget.repository
          .updateRecord(widget.jobId, widget.exercise.id, {
            'question': _question.text,
            'correct_answer': _answer.text,
            if (_explanation.text.isNotEmpty) 'explanation': _explanation.text,
            if (options != null) 'options': options,
            if (_outcome.text.isNotEmpty) 'lesson_outcome': _outcome.text,
          });
      if (mounted) Navigator.pop(context, preview);
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'adminGrowth.qa.saveFailed'.tr();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      20,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'adminGrowth.qa.editExercise'.tr(),
            style: Theme.of(context).textTheme.heading?.copyWith(
              fontWeight: FontWeight.w700,
              color: context.toneText,
            ),
          ),
          Text(
            widget.lesson.title,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.toneMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          _Field(
            controller: _question,
            label: 'adminGrowth.qa.question'.tr(),
            lines: 2,
          ),
          _Field(
            controller: _options,
            label: 'adminGrowth.qa.optionsJson'.tr(),
            lines: 3,
          ),
          _Field(
            controller: _answer,
            label: 'adminGrowth.qa.correctAnswer'.tr(),
          ),
          _Field(
            controller: _explanation,
            label: 'adminGrowth.qa.explanation'.tr(),
            lines: 2,
          ),
          _Field(
            controller: _outcome,
            label: 'adminGrowth.qa.outcome'.tr(),
            lines: 2,
          ),
          if (_error != null)
            Text(_error!, style: context.adminStyle(color: context.toneDanger)),
          const SizedBox(height: AppSpacing.md),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(
              _saving
                  ? 'adminGrowth.qa.saving'.tr()
                  : 'adminGrowth.common.save'.tr(),
            ),
          ),
        ],
      ),
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
      style: context.adminStyle(color: context.toneText),
      decoration: InputDecoration(
        labelText: label,
        alignLabelWithHint: lines > 1,
      ),
    ),
  );
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String message;
  const _MessageCard({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.xl),
    decoration: BoxDecoration(
      color: context.toneCard,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: context.toneLine, width: 0.5),
    ),
    child: Column(
      children: [
        Icon(icon, size: 32, color: context.toneMuted),
        const SizedBox(height: AppSpacing.sm),
        Text(
          message,
          textAlign: TextAlign.center,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: context.toneMuted),
        ),
      ],
    ),
  );
}

class _QueueSkeleton extends StatelessWidget {
  const _QueueSkeleton();

  @override
  Widget build(BuildContext context) => const Column(
    children: [
      SkeletonBox(height: 44, borderRadius: 22),
      SizedBox(height: AppSpacing.lg),
      ListRowSkeleton(),
      ListRowSkeleton(),
      ListRowSkeleton(),
    ],
  );
}
