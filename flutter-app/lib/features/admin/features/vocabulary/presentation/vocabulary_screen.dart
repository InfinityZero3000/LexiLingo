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
import '../data/vocabulary_repository.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key, this.repository});

  final VocabularyRepository? repository;

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  late final VocabularyRepository _repo =
      widget.repository ?? VocabularyRepository();
  late final AdminPager<VocabularyWord> _pager = AdminPager(
    load: (request, _) => _repo.list(request),
  );

  @override
  void dispose() {
    _pager.dispose();
    super.dispose();
  }

  Future<void> _edit([VocabularyWord? word]) async {
    final wordCtrl = TextEditingController(text: word?.word);
    final definition = TextEditingController(text: word?.definition);
    final translation = TextEditingController(text: word?.translation);
    final pronunciation = TextEditingController(text: word?.pronunciation);
    var part = vocabularyParts.contains(word?.partOfSpeech)
        ? word!.partOfSpeech
        : 'noun';
    var level = word?.level ?? 'A1';
    final saved = await showAdminFormSheet(
      context,
      title: word == null
          ? 'admin.vocabulary.new'.tr()
          : 'admin.vocabulary.edit'.tr(),
      validate: () =>
          wordCtrl.text.trim().isNotEmpty &&
          definition.text.trim().isNotEmpty &&
          translation.text.trim().isNotEmpty,
      builder: (_) => [
        AppTextField(controller: wordCtrl, label: 'admin.vocabulary.word'.tr()),
        AppTextField(
          controller: definition,
          label: 'admin.vocabulary.definition'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: translation,
          label: 'admin.vocabulary.translation'.tr(),
        ),
        AppTextField(
          controller: pronunciation,
          label: 'admin.vocabulary.pronunciation'.tr(),
        ),
        StatefulBuilder(
          builder: (context, set) => Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: part,
                  decoration: InputDecoration(
                    labelText: 'admin.vocabulary.partOfSpeech'.tr(),
                  ),
                  items: [
                    for (final v in vocabularyParts)
                      DropdownMenuItem(value: v, child: Text(v)),
                  ],
                  onChanged: (v) => set(() => part = v!),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: DropdownButtonFormField<String>(
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
              ),
            ],
          ),
        ),
      ],
      onSubmit: () => _repo.save(
        id: word?.id,
        word: wordCtrl.text.trim(),
        definition: definition.text.trim(),
        translation: translation.text.trim(),
        partOfSpeech: part,
        pronunciation: pronunciation.text.trim(),
        level: level,
      ),
    );
    for (final c in [wordCtrl, definition, translation, pronunciation]) {
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
      title: 'admin.nav.vocabulary'.tr(),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _edit,
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.vocabulary.new'.tr()),
            )
          : null,
      body: AdminPagedList<VocabularyWord>(
        pager: _pager,
        emptyTitle: 'admin.vocabulary.empty'.tr(),
        emptyIcon: Icons.book_outlined,
        header: const Padding(
          padding: EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            0,
          ),
          child: AdminWebOnlyTile(),
        ),
        itemBuilder: (context, word, _) => AdminItemCard(
          title: word.word,
          subtitle: [
            word.definition,
            if (word.translation != null) word.translation!,
          ].join(' · '),
          badges: [
            StatusPill(label: word.level, tone: StatusTone.info),
            StatusPill(label: word.partOfSpeech),
          ],
          onTap: canUpdate ? () => _edit(word) : null,
        ),
      ),
    );
  }
}
