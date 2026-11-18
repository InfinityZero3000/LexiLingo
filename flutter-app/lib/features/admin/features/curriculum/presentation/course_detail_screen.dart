import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_form_sheet.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../data/curriculum_repository.dart';

class CourseDetailScreen extends StatefulWidget {
  const CourseDetailScreen({
    super.key,
    required this.courseId,
    this.repository,
  });

  final String courseId;
  final CurriculumRepository? repository;

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  late final CurriculumRepository _repo =
      widget.repository ?? CurriculumRepository();
  late final AdminPager<Unit> _pager = AdminPager(
    pageSize: 200,
    load: (_, __) => _repo.listUnits(widget.courseId),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([Unit? unit]) async {
    final title = TextEditingController(text: unit?.title);
    final description = TextEditingController(text: unit?.description);
    final order = TextEditingController(
      text: '${unit?.orderIndex ?? _pager.controller.items.length}',
    );
    final saved = await showAdminFormSheet(
      context,
      controllers: [title, description, order],
      title: unit == null ? 'admin.units.new'.tr() : 'admin.units.edit'.tr(),
      validate: () =>
          title.text.trim().isNotEmpty &&
          int.tryParse(order.text.trim()) != null,
      builder: (_) => [
        AppTextField(controller: title, label: 'admin.content.title'.tr()),
        AppTextField(
          controller: description,
          label: 'admin.content.description'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: order,
          label: 'admin.categories.order'.tr(),
          keyboardType: TextInputType.number,
        ),
      ],
      onSubmit: () {
        final data = {
          'title': title.text.trim(),
          'description': description.text.trim(),
          'order_index': int.parse(order.text.trim()),
        };
        return unit == null
            ? _repo.createUnit({...data, 'course_id': widget.courseId})
            : _repo.updateUnit(unit.id, data);
      },
    );
    for (final c in [title, description, order]) {
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
      title: 'admin.units.title'.tr(),
      showMenu: false,
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.units.new'.tr()),
            )
          : null,
      body: AdminPagedList<Unit>(
        pager: _pager,
        emptyTitle: 'admin.units.empty'.tr(),
        emptyIcon: Icons.view_module_outlined,
        itemBuilder: (context, unit, _) => AdminItemCard(
          title: '${unit.orderIndex + 1}. ${unit.title}',
          subtitle: unit.description,
          badges: [
            StatusPill(
              label: 'admin.units.lessons'.tr(
                namedArgs: {'count': '${unit.lessonCount}'},
              ),
              tone: StatusTone.info,
            ),
          ],
          trailing: canUpdate
              ? IconButton(
                  tooltip: 'common.edit'.tr(),
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _edit(unit),
                )
              : null,
          onTap: () => context.push(
            '/curriculum/units',
            extra: {'unitId': unit.id, 'unitTitle': unit.title},
          ),
        ),
      ),
    );
  }
}
