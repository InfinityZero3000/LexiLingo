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
import '../../vocabulary/data/vocabulary_repository.dart' show vocabularyLevels;
import '../data/grammar_repository.dart';

class GrammarTestsScreen extends StatefulWidget {
  const GrammarTestsScreen({super.key, this.repository});

  final GrammarRepository? repository;

  @override
  State<GrammarTestsScreen> createState() => _GrammarTestsScreenState();
}

class _GrammarTestsScreenState extends State<GrammarTestsScreen> {
  late final GrammarRepository _repo = widget.repository ?? GrammarRepository();
  late final AdminPager<GrammarRule> _pager = AdminPager(
    load: (request, _) => _repo.list(request),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([GrammarRule? rule]) async {
    final title = TextEditingController(text: rule?.title);
    final topic = TextEditingController(text: rule?.topic);
    final summary = TextEditingController(text: rule?.summary);
    final content = TextEditingController(text: rule?.content);
    final tags = TextEditingController(text: rule?.tags.join(', '));
    var level = rule?.level ?? 'A1';
    var active = rule?.isActive ?? true;
    final saved = await showAdminFormSheet(
      context,
      title: rule == null
          ? 'admin.grammar.new'.tr()
          : 'admin.grammar.edit'.tr(),
      validate: () =>
          title.text.trim().isNotEmpty && content.text.trim().isNotEmpty,
      builder: (_) => [
        AppTextField(controller: title, label: 'admin.content.title'.tr()),
        AppTextField(controller: topic, label: 'admin.grammar.topic'.tr()),
        AppTextField(
          controller: summary,
          label: 'admin.grammar.summary'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: content,
          label: 'admin.grammar.content'.tr(),
          minLines: 3,
          maxLines: 8,
        ),
        AppTextField(
          controller: tags,
          label: 'admin.content.tags'.tr(),
          hint: 'admin.content.tagsHint'.tr(),
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
                title: Text('admin.content.active'.tr()),
                value: active,
                onChanged: (v) => set(() => active = v),
              ),
            ],
          ),
        ),
      ],
      onSubmit: () => _repo.save(
        id: rule?.id,
        data: {
          'title': title.text.trim(),
          'level': level,
          'topic': topic.text.trim(),
          'summary': summary.text.trim(),
          'content': content.text.trim(),
          'tags': [
            for (final t in tags.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
          'is_active': active,
        },
      ),
    );
    for (final c in [title, topic, summary, content, tags]) {
      c.dispose();
    }
    if (saved) await _pager.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('content:create');
    final canUpdate = permissions.can('content:update');
    return AdminPage(
      title: 'admin.nav.grammar'.tr(),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.grammar.new'.tr()),
            )
          : null,
      body: AdminPagedList<GrammarRule>(
        pager: _pager,
        emptyTitle: 'admin.grammar.empty'.tr(),
        emptyIcon: Icons.quiz_outlined,
        header: const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: AdminWebOnlyTile(),
        ),
        itemBuilder: (context, rule, _) => AdminItemCard(
          title: rule.title,
          subtitle: rule.summary ?? rule.topic,
          badges: [
            StatusPill(label: rule.level, tone: StatusTone.info),
            if (!rule.isActive)
              StatusPill(
                label: 'admin.content.inactive'.tr(),
                tone: StatusTone.warning,
              ),
          ],
          onTap: canUpdate ? () => _edit(rule) : null,
        ),
      ),
    );
  }
}
