import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_form_sheet.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../data/curriculum_repository.dart';

const _lessonTypes = [
  'lesson',
  'practice',
  'review',
  'test',
  'vocabulary',
  'grammar',
];

/// An empty string is the picker's "inherit from the course" choice; the API
/// takes a real skill name or null.
const _skills = [
  '',
  'vocabulary',
  'grammar',
  'reading',
  'listening',
  'speaking',
  'writing',
];

class UnitsLessonsScreen extends StatefulWidget {
  const UnitsLessonsScreen({
    super.key,
    required this.unitId,
    required this.unitTitle,
    this.repository,
  });

  final String unitId;
  final String unitTitle;
  final CurriculumRepository? repository;

  @override
  State<UnitsLessonsScreen> createState() => _UnitsLessonsScreenState();
}

class _UnitsLessonsScreenState extends State<UnitsLessonsScreen> {
  late final CurriculumRepository _repo =
      widget.repository ?? CurriculumRepository();
  late final AdminPager<Lesson> _pager = AdminPager(
    pageSize: 200,
    load: (_, __) => _repo.listLessons(widget.unitId),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([Lesson? lesson]) async {
    final title = TextEditingController(text: lesson?.title);
    final description = TextEditingController(text: lesson?.description);
    final outcome = TextEditingController(text: lesson?.outcome);
    final xp = TextEditingController(text: '${lesson?.xpReward ?? 10}');
    final threshold = TextEditingController(
      text: '${lesson?.passThreshold ?? 80}',
    );
    final minutes = TextEditingController(
      text: '${lesson?.estimatedMinutes ?? 10}',
    );
    var type = _lessonTypes.contains(lesson?.lessonType)
        ? lesson!.lessonType
        : 'lesson';
    var skill = _skills.contains(lesson?.skill) ? (lesson?.skill ?? '') : '';
    final saved = await showAdminFormSheet(
      context,
      controllers: [title, description, outcome, xp, threshold, minutes],
      title: lesson == null
          ? 'admin.lessons.new'.tr()
          : 'admin.lessons.edit'.tr(),
      validate: () =>
          title.text.trim().isNotEmpty &&
          int.tryParse(xp.text.trim()) != null &&
          int.tryParse(threshold.text.trim()) != null &&
          int.tryParse(minutes.text.trim()) != null,
      builder: (_) => [
        AppTextField(controller: title, label: 'admin.content.title'.tr()),
        AppTextField(
          controller: description,
          label: 'admin.content.description'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: outcome,
          label: 'admin.lessons.outcome'.tr(),
          maxLines: 2,
        ),
        StatefulBuilder(
          builder: (context, set) => Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: type,
                decoration: InputDecoration(
                  labelText: 'admin.lessons.type'.tr(),
                ),
                items: [
                  for (final v in _lessonTypes)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => set(() => type = v!),
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String>(
                initialValue: skill,
                decoration: InputDecoration(
                  labelText: 'admin.lessons.skill'.tr(),
                ),
                items: [
                  for (final v in _skills)
                    DropdownMenuItem(
                      value: v,
                      child: Text(
                        v.isEmpty ? 'admin.lessons.inheritSkill'.tr() : v,
                      ),
                    ),
                ],
                onChanged: (v) => set(() => skill = v ?? ''),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Expanded(
              child: AppTextField(
                controller: xp,
                label: 'admin.lessons.xp'.tr(),
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: AppTextField(
                controller: threshold,
                label: 'admin.lessons.passPercent'.tr(),
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        AppTextField(
          controller: minutes,
          label: 'admin.lessons.minutes'.tr(),
          keyboardType: TextInputType.number,
        ),
      ],
      onSubmit: () {
        final data = {
          'title': title.text.trim(),
          'description': description.text.trim(),
          'outcome': outcome.text.trim(),
          'lesson_type': type,
          'skill': skill.isEmpty ? null : skill,
          'xp_reward': int.parse(xp.text.trim()),
          'pass_threshold': int.parse(threshold.text.trim()),
          'estimated_minutes': int.parse(minutes.text.trim()),
          'order_index': lesson?.orderIndex ?? _pager.controller.items.length,
        };
        return lesson == null
            ? _repo.createLesson({...data, 'unit_id': widget.unitId})
            : _repo.updateLesson(lesson.id, data);
      },
    );
    for (final c in [title, description, outcome, xp, threshold, minutes]) {
      c.dispose();
    }
    if (saved) await _pager.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('courses:create');
    final canUpdate = permissions.can('courses:update');
    return AdminPage(
      title: widget.unitTitle,
      showMenu: false,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.lessons.new'.tr()),
            )
          : null,
      body: AdminPagedList<Lesson>(
        pager: _pager,
        emptyTitle: 'admin.lessons.empty'.tr(),
        emptyIcon: Icons.school_outlined,
        itemBuilder: (context, lesson, _) => AdminItemCard(
          title: '${lesson.orderIndex + 1}. ${lesson.title}',
          subtitle: lesson.outcome ?? lesson.description,
          badges: [
            StatusPill(label: lesson.lessonType, tone: StatusTone.info),
            StatusPill(
              label: 'admin.lessons.exercises'.tr(
                namedArgs: {'count': '${lesson.totalExercises}'},
              ),
              tone: lesson.totalExercises == 0
                  ? StatusTone.warning
                  : StatusTone.neutral,
            ),
            StatusPill(
              label: 'admin.lessons.xpValue'.tr(
                namedArgs: {'count': '${lesson.xpReward}'},
              ),
            ),
          ],
          trailing: canUpdate
              ? IconButton(
                  tooltip: 'common.edit'.tr(),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(lesson),
                )
              : null,
          onTap: () => context.push(
            '/curriculum/lesson/${lesson.id}',
            extra: {'lessonTitle': lesson.title},
          ),
        ),
      ),
    );
  }
}
