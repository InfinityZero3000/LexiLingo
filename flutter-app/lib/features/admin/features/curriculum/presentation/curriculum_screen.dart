import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/core/widgets/debounced_search_field.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_form_sheet.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../../../shared/widgets/admin_web_only_tile.dart';
import '../../vocabulary/data/vocabulary_repository.dart' show vocabularyLevels;
import '../data/curriculum_repository.dart';

class CurriculumScreen extends StatefulWidget {
  const CurriculumScreen({super.key, this.repository});

  final CurriculumRepository? repository;

  @override
  State<CurriculumScreen> createState() => _CurriculumScreenState();
}

class _CurriculumScreenState extends State<CurriculumScreen> {
  late final CurriculumRepository _repo =
      widget.repository ?? CurriculumRepository();
  late final AdminPager<Course> _pager = AdminPager(
    load: (request, filters) => _repo.listCourses(request, filters),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _edit([Course? course]) async {
    final title = TextEditingController(text: course?.title);
    final description = TextEditingController(text: course?.description);
    final language = TextEditingController(text: course?.language ?? 'en');
    final tags = TextEditingController(text: course?.tags.join(', '));
    final thumbnail = TextEditingController(text: course?.thumbnailUrl);
    var level = course?.level ?? 'A1';
    var published = course?.isPublished ?? false;
    final saved = await showAdminFormSheet(
      context,
      title: course == null
          ? 'admin.courses.new'.tr()
          : 'admin.courses.edit'.tr(),
      validate: () =>
          title.text.trim().isNotEmpty && language.text.trim().isNotEmpty,
      builder: (_) => [
        AppTextField(controller: title, label: 'admin.content.title'.tr()),
        AppTextField(
          controller: description,
          label: 'admin.content.description'.tr(),
          maxLines: 3,
        ),
        AppTextField(
          controller: language,
          label: 'admin.courses.language'.tr(),
        ),
        AppTextField(controller: tags, label: 'admin.content.tags'.tr()),
        AppTextField(
          controller: thumbnail,
          label: 'admin.courses.thumbnail'.tr(),
          keyboardType: TextInputType.url,
        ),
        StatefulBuilder(
          builder: (context, set) => Column(
            children: [
              DropdownButtonFormField<String>(
                initialValue: level,
                decoration: InputDecoration(
                  labelText: 'admin.content.level'.tr(),
                ),
                items: [
                  for (final v in vocabularyLevels)
                    DropdownMenuItem(value: v, child: Text(v)),
                ],
                onChanged: (v) => set(() => level = v!),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('admin.content.published'.tr()),
                value: published,
                onChanged: (v) => set(() => published = v),
              ),
            ],
          ),
        ),
      ],
      onSubmit: () {
        final data = {
          'title': title.text.trim(),
          'description': description.text.trim(),
          'language': language.text.trim(),
          'level': level,
          'is_published': published,
          'thumbnail_url': thumbnail.text.trim().isEmpty
              ? null
              : thumbnail.text.trim(),
          'tags': [
            for (final t in tags.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
        };
        return course == null
            ? _repo.createCourse(data)
            : _repo.updateCourse(course.id, data);
      },
    );
    for (final c in [title, description, language, tags, thumbnail]) {
      c.dispose();
    }
    if (saved) await _pager.controller.refresh();
  }

  Future<void> _togglePublish(Course course) async {
    final publish = !course.isPublished;
    final ok = await showConfirm(
      context,
      title: publish
          ? 'admin.courses.publishTitle'.tr()
          : 'admin.courses.unpublishTitle'.tr(),
      message: course.title,
      confirmLabel: publish
          ? 'admin.courses.publish'.tr()
          : 'admin.courses.unpublish'.tr(),
    );
    if (!ok || !mounted) return;
    try {
      publish
          ? await _repo.publishCourse(course.id)
          : await _repo.unpublishCourse(course.id);
      await _pager.controller.refresh();
    } catch (e) {
      if (mounted) _toast(AdminApiError.from(e).message.resolve());
    }
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('courses:create');
    final canUpdate = permissions.can('courses:update');
    final c = _pager.controller;
    return AdminPage(
      title: 'admin.nav.courses'.tr(),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.courses.new'.tr()),
            )
          : null,
      body: AdminPagedList<Course>(
        pager: _pager,
        emptyTitle: 'admin.courses.empty'.tr(),
        emptyIcon: Icons.menu_book_outlined,
        header: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: DebouncedSearchField(
                hint: 'admin.courses.search'.tr(),
                onChanged: (q) => c.setFilter('search', q.isEmpty ? null : q),
              ),
            ),
            ListenableBuilder(
              listenable: c,
              builder: (context, _) => Column(
                children: [
                  FilterChipBar<String>(
                    options: [
                      for (final v in vocabularyLevels)
                        FilterOption(value: v, label: v),
                    ],
                    selected: c.filters['level'] as String?,
                    onSelected: (v) => c.setFilter('level', v),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  FilterChipBar<bool>(
                    options: [
                      FilterOption(
                        value: true,
                        label: 'admin.content.published'.tr(),
                      ),
                      FilterOption(
                        value: false,
                        label: 'admin.content.draft'.tr(),
                      ),
                    ],
                    selected: c.filters['is_published'] as bool?,
                    onSelected: (v) => c.setFilter('is_published', v),
                  ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(AppSpacing.lg),
              child: AdminWebOnlyTile(),
            ),
          ],
        ),
        itemBuilder: (context, course, _) => AdminItemCard(
          title: course.title,
          subtitle: course.description,
          badges: [
            StatusPill(label: course.level, tone: StatusTone.info),
            StatusPill(
              label: course.isPublished
                  ? 'admin.content.published'.tr()
                  : 'admin.content.draft'.tr(),
              tone: course.isPublished
                  ? StatusTone.success
                  : StatusTone.neutral,
            ),
            StatusPill(
              label: 'admin.courses.counts'.tr(
                namedArgs: {
                  'units': '${course.unitCount}',
                  'lessons': '${course.lessonCount}',
                },
              ),
            ),
          ],
          trailing: canUpdate
              ? PopupMenuButton<String>(
                  tooltip: 'admin.content.actions'.tr(),
                  onSelected: (v) =>
                      v == 'edit' ? _edit(course) : _togglePublish(course),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'edit',
                      child: Text('common.edit'.tr()),
                    ),
                    PopupMenuItem(
                      value: 'publish',
                      child: Text(
                        course.isPublished
                            ? 'admin.courses.unpublish'.tr()
                            : 'admin.courses.publish'.tr(),
                      ),
                    ),
                  ],
                )
              : null,
          onTap: () => context.push('/curriculum/course/${course.id}'),
        ),
      ),
    );
  }
}
