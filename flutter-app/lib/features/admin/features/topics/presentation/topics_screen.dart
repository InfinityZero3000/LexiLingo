import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_form_sheet.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../data/topics_repository.dart';

List<String> _split(String value) => [
  for (final p in value.split(','))
    if (p.trim().isNotEmpty) p.trim(),
];

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key, this.repository});

  final TopicsRepository? repository;

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  late final TopicsRepository _repo = widget.repository ?? TopicsRepository();
  late final AdminPager<TopicItem> _pager = AdminPager(
    pageSize: 200,
    load: (_, __) => _repo.list(),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([TopicItem? topic]) async {
    final titleEn = TextEditingController(text: topic?.titleEn);
    final titleVi = TextEditingController(text: topic?.titleVi);
    final category = TextEditingController(text: topic?.category ?? 'travel');
    final minutes = TextEditingController(text: '${topic?.minutes ?? 15}');
    final icon = TextEditingController(text: topic?.iconKey ?? 'travel');
    final opening = TextEditingController();
    final prompts = TextEditingController(
      text: topic?.suggestedPrompts.join(', '),
    );
    final tags = TextEditingController(text: topic?.tags.join(', '));
    var difficulty = topicDifficulties.contains(topic?.difficulty)
        ? topic!.difficulty
        : 'A2';
    final saved = await showAdminFormSheet(
      context,
      title: topic == null ? 'admin.topics.new'.tr() : 'admin.topics.edit'.tr(),
      validate: () =>
          titleEn.text.trim().isNotEmpty &&
          category.text.trim().isNotEmpty &&
          (int.tryParse(minutes.text.trim()) ?? 0) > 0,
      builder: (_) => [
        AppTextField(controller: titleEn, label: 'admin.topics.titleEn'.tr()),
        AppTextField(controller: titleVi, label: 'admin.topics.titleVi'.tr()),
        StatefulBuilder(
          builder: (context, set) => DropdownButtonFormField<String>(
            initialValue: difficulty,
            decoration: InputDecoration(labelText: 'admin.content.level'.tr()),
            items: [
              for (final v in topicDifficulties)
                DropdownMenuItem(value: v, child: Text(v)),
            ],
            onChanged: (v) => set(() => difficulty = v!),
          ),
        ),
        AppTextField(controller: category, label: 'admin.topics.category'.tr()),
        AppTextField(
          controller: minutes,
          label: 'admin.topics.minutes'.tr(),
          keyboardType: TextInputType.number,
        ),
        AppTextField(controller: icon, label: 'admin.topics.icon'.tr()),
        AppTextField(
          controller: opening,
          label: 'admin.topics.opening'.tr(),
          maxLines: 3,
        ),
        AppTextField(
          controller: prompts,
          label: 'admin.topics.suggested'.tr(),
          hint: 'admin.content.tagsHint'.tr(),
        ),
        AppTextField(controller: tags, label: 'admin.content.tags'.tr()),
      ],
      onSubmit: () => _repo.save(
        storyId: topic?.storyId,
        titleEn: titleEn.text.trim(),
        titleVi: titleVi.text.trim(),
        difficulty: difficulty,
        category: category.text.trim(),
        minutes: int.parse(minutes.text.trim()),
        iconKey: icon.text.trim().isEmpty
            ? category.text.trim()
            : icon.text.trim(),
        openingPrompt: opening.text.trim(),
        suggestedPrompts: _split(prompts.text),
        tags: _split(tags.text),
      ),
    );
    for (final c in [
      titleEn,
      titleVi,
      category,
      minutes,
      icon,
      opening,
      prompts,
      tags,
    ]) {
      c.dispose();
    }
    if (saved) await _pager.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('topics:create');
    return AdminPage(
      title: 'admin.nav.topics'.tr(),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.topics.new'.tr()),
            )
          : null,
      body: AdminPagedList<TopicItem>(
        pager: _pager,
        emptyTitle: 'admin.topics.empty'.tr(),
        emptyIcon: Icons.forum_outlined,
        itemBuilder: (context, t, _) => AdminItemCard(
          title: t.titleEn,
          subtitle: t.titleVi == t.titleEn ? t.category : t.titleVi,
          badges: [
            StatusPill(label: t.difficulty, tone: StatusTone.info),
            StatusPill(label: t.category),
            StatusPill(
              label: 'admin.topics.minutesShort'.tr(
                namedArgs: {'count': '${t.minutes}'},
              ),
            ),
          ],
          onTap: canCreate ? () => _edit(t) : null,
        ),
      ),
    );
  }
}
