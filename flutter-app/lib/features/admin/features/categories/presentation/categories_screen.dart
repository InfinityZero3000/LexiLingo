import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_form_sheet.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../../../shared/widgets/admin_web_only_tile.dart';
import '../data/categories_repository.dart';

class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.repository});

  final CategoriesRepository? repository;

  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  late final CategoriesRepository _repo =
      widget.repository ?? CategoriesRepository();
  late final AdminPager<CourseCategory> _pager = AdminPager(
    pageSize: 100,
    load: (_, __) => _repo.list(),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([CourseCategory? category]) async {
    final name = TextEditingController(text: category?.name);
    final slug = TextEditingController(text: category?.slug);
    final description = TextEditingController(text: category?.description);
    final icon = TextEditingController(text: category?.icon);
    final color = TextEditingController(text: category?.color);
    final order = TextEditingController(text: '${category?.orderIndex ?? 0}');
    var active = category?.isActive ?? true;
    final saved = await showAdminFormSheet(
      context,
      controllers: [name, slug, description, icon, color, order],
      title: category == null
          ? 'admin.categories.new'.tr()
          : 'admin.categories.edit'.tr(),
      validate: () =>
          name.text.trim().isNotEmpty &&
          slug.text.trim().isNotEmpty &&
          int.tryParse(order.text.trim()) != null,
      builder: (_) => [
        AppTextField(controller: name, label: 'admin.content.name'.tr()),
        AppTextField(controller: slug, label: 'admin.categories.slug'.tr()),
        AppTextField(
          controller: description,
          label: 'admin.content.description'.tr(),
          maxLines: 2,
        ),
        AppTextField(controller: icon, label: 'admin.categories.icon'.tr()),
        AppTextField(controller: color, label: 'admin.categories.color'.tr()),
        AppTextField(
          controller: order,
          label: 'admin.categories.order'.tr(),
          keyboardType: TextInputType.number,
        ),
        StatefulBuilder(
          builder: (context, set) => SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('admin.content.active'.tr()),
            value: active,
            onChanged: (v) => set(() => active = v),
          ),
        ),
      ],
      onSubmit: () => _repo.save(
        id: category?.id,
        data: {
          'name': name.text.trim(),
          'slug': slug.text.trim(),
          'description': description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          'icon': icon.text.trim().isEmpty ? null : icon.text.trim(),
          'color': color.text.trim().isEmpty ? null : color.text.trim(),
          'order_index': int.parse(order.text.trim()),
          'is_active': active,
        },
      ),
    );
    for (final c in [name, slug, description, icon, color, order]) {
      c.dispose();
    }
    if (saved) await _pager.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('categories:create');
    final canUpdate = permissions.can('categories:update');
    return AdminPage(
      title: 'admin.nav.categories'.tr(),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.categories.new'.tr()),
            )
          : null,
      body: AdminPagedList<CourseCategory>(
        pager: _pager,
        emptyTitle: 'admin.categories.empty'.tr(),
        emptyIcon: Icons.category_outlined,
        header: const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: AdminWebOnlyTile(),
        ),
        itemBuilder: (context, c, _) => AdminItemCard(
          title: c.name,
          subtitle: c.description ?? c.slug,
          badges: [
            StatusPill(
              label: 'admin.categories.courses'.tr(
                namedArgs: {'count': '${c.courseCount}'},
              ),
              tone: StatusTone.info,
            ),
            if (!c.isActive)
              StatusPill(
                label: 'admin.content.inactive'.tr(),
                tone: StatusTone.warning,
              ),
          ],
          onTap: canUpdate ? () => _edit(c) : null,
        ),
      ),
    );
  }
}
