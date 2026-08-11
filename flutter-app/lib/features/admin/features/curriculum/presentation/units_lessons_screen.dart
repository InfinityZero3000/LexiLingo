import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/curriculum_repository.dart';

class UnitsLessonsScreen extends StatefulWidget {
  final String unitId;
  final String unitTitle;

  const UnitsLessonsScreen({
    super.key,
    required this.unitId,
    required this.unitTitle,
  });

  @override
  State<UnitsLessonsScreen> createState() => _UnitsLessonsScreenState();
}

class _UnitsLessonsScreenState extends State<UnitsLessonsScreen> {
  final _repo = CurriculumRepository();
  List<Lesson> _lessons = [];
  bool _loading = true;
  String? _expandedId;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final lessons = await _repo.getLessons(widget.unitId);
      if (mounted) setState(() { _lessons = lessons; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load lessons.'; });
    }
  }

  Future<void> _edit([Lesson? lesson]) async {
    final title = TextEditingController(text: lesson?.title);
    final description = TextEditingController(text: lesson?.description);
    final outcome = TextEditingController(text: lesson?.outcome);
    final xp = TextEditingController(text: '${lesson?.xpReward ?? 10}');
    final threshold = TextEditingController(text: '${lesson?.passThreshold ?? 80}');
    final minutes = TextEditingController(text: '${lesson?.estimatedMinutes ?? 10}');
    var type = lesson?.lessonType ?? 'lesson';
    final saved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(builder: (context, setDialogState) => AlertDialog(
      title: Text(lesson == null ? 'Create lesson' : 'Edit lesson'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Title *')),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        TextField(controller: outcome, maxLines: 2, decoration: const InputDecoration(labelText: 'Outcome')),
        DropdownButtonFormField<String>(initialValue: type, decoration: const InputDecoration(labelText: 'Type'), items: ['lesson','practice','review','test','vocabulary','grammar'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setDialogState(() => type = v!)),
        Row(children: [Expanded(child: TextField(controller: xp, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'XP'))), const SizedBox(width: 8), Expanded(child: TextField(controller: threshold, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Pass %')))]),
        TextField(controller: minutes, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, title.text.trim().isNotEmpty), child: const Text('Save'))])));
    if (saved != true) return;
    final data = {'title': title.text.trim(), 'description': description.text.trim(), 'outcome': outcome.text.trim(), 'lesson_type': type, 'xp_reward': int.tryParse(xp.text) ?? 10, 'pass_threshold': int.tryParse(threshold.text) ?? 80, 'estimated_minutes': int.tryParse(minutes.text) ?? 10, 'order_index': lesson?.orderIndex ?? _lessons.length};
    try { if (lesson == null) { await _repo.createLesson({...data, 'unit_id': widget.unitId}); } else { await _repo.updateLesson(lesson.id, data); } await _load(); }
    catch (_) { if (mounted) setState(() => _error = 'Could not save lesson.'); }
  }

  Future<void> _delete(Lesson lesson) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete lesson?'), content: Text('Delete “${lesson.title}”?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (ok == true) { try { await _repo.deleteLesson(lesson.id); await _load(); } catch (_) { if (mounted) setState(() => _error = 'Could not delete lesson.'); } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Lessons in ${widget.unitTitle}',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        leading: AppBackButton(
          icon: Icons.arrow_back,
          color: AppColors.onSurface,
          onPressed: () => context.pop(),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh), tooltip: 'Refresh'),
        ],
      ),
      body: _loading
          ? const Padding(padding: EdgeInsets.all(20), child: Column(children: [AdminSkeleton(height: 100), SizedBox(height: 12), AdminSkeleton(height: 100)]))
          : Column(
              children: [
                if (_error != null) Padding(padding: const EdgeInsets.fromLTRB(20, 12, 20, 0), child: Row(children: [const Icon(Icons.error_outline, color: AppColors.error), const SizedBox(width: 8), Expanded(child: Text(_error!, style: GoogleFonts.spaceGrotesk(color: AppColors.error))), TextButton(onPressed: _load, child: const Text('Retry'))])),
                Expanded(
                  child: RefreshIndicator(onRefresh: _load, child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _lessons.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == _lessons.length) {
                        return GestureDetector(
                          onTap: _edit,
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.outlineVariant, width: 1.5, style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add, size: 16, color: AppColors.onSurfaceMuted),
                                  const SizedBox(width: 6),
                                  Text('ADD NEW LESSON',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.05,
                                          color: AppColors.onSurfaceMuted)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final lesson = _lessons[i];
                      final isExpanded = _expandedId == lesson.id;
                      return _LessonCard(
                        lesson: lesson,
                        index: i + 1,
                        isExpanded: isExpanded,
                        onTap: () => setState(() {
                          _expandedId = isExpanded ? null : lesson.id;
                        }),
                        onEdit: () => _edit(lesson),
                        onDelete: () => _delete(lesson),
                        onManageExercises: () => context.push(
                          '/curriculum/lesson/${lesson.id}',
                          extra: {'lessonTitle': lesson.title},
                        ),
                      );
                    },
                  )),
                ),
              ],
            ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final int index;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onManageExercises;

  const _LessonCard({
    required this.lesson,
    required this.index,
    required this.isExpanded,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onManageExercises,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? AppColors.primary : AppColors.outlineVariant,
            width: isExpanded ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isExpanded ? AppColors.primary : AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$index.${lesson.orderIndex}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isExpanded ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.title,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        if (lesson.description != null)
                          Text(
                            lesson.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12, color: AppColors.onSurfaceMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lesson.lessonType.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        onEdit();
                      } else if (v == 'delete') {
                        onDelete();
                      } else {
                        onManageExercises();
                      }
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'exercises', child: Text('Manage exercises')),
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CONTENT MODULES',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
                              const SizedBox(height: 8),
                              _ModuleRow(icon: Icons.fitness_center, label: '${lesson.totalExercises} exercises'),
                              const SizedBox(height: 6),
                              _ModuleRow(icon: Icons.schedule, label: '${lesson.estimatedMinutes} minutes'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('QUIZ PROGRESS',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('${lesson.xpReward} XP',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12, color: AppColors.onSurfaceVariant)),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('${lesson.passThreshold}% PASS',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.warning)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: lesson.passThreshold.clamp(0, 100) / 100,
                                  backgroundColor: AppColors.surfaceContainerHigh,
                                  valueColor: AlwaysStoppedAnimation(AppColors.warning),
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ModuleRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurface)),
        ),
      ],
    );
  }
}
