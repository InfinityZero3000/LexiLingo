import 'dart:convert';

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
import '../data/content_lab_repository.dart';

const _questionTypes = ['mcq', 'fill_blank', 'true_false'];

class ContentLabScreen extends StatefulWidget {
  const ContentLabScreen({super.key, this.repository});

  final ContentLabRepository? repository;

  @override
  State<ContentLabScreen> createState() => _ContentLabScreenState();
}

class _ContentLabScreenState extends State<ContentLabScreen>
    with SingleTickerProviderStateMixin {
  late final ContentLabRepository _repo =
      widget.repository ?? ContentLabRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this)
    ..addListener(() => setState(() {}));
  late final AdminPager<QuestionItem> _questions = AdminPager(
    load: (request, _) => _repo.listQuestions(request),
  );
  late final AdminPager<TestExam> _exams = AdminPager(
    load: (request, _) => _repo.listTestExams(request),
  );

  @override
  void dispose() {
    _tabs.dispose();
    _questions.dispose();
    _exams.dispose();
    super.dispose();
  }

  Widget _dropdown(
    String label,
    String value,
    List<String> options,
    ValueChanged<String> onChanged,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final v in options) DropdownMenuItem(value: v, child: Text(v)),
    ],
    onChanged: (v) => onChanged(v!),
  );

  Future<void> _editQuestion([QuestionItem? item]) async {
    final prompt = TextEditingController(text: item?.prompt);
    final options = TextEditingController(
      text: item == null ? '' : jsonEncode(item.options),
    );
    final answer = TextEditingController(
      text: item?.answer == null ? '' : jsonEncode(item!.answer),
    );
    final explanation = TextEditingController(text: item?.explanation);
    final tags = TextEditingController(text: item?.tags.join(', '));
    var type = _questionTypes.contains(item?.questionType)
        ? item!.questionType
        : 'mcq';
    var level = item?.difficultyLevel ?? 'A1';
    var active = item?.isActive ?? true;
    List<dynamic>? parsedOptions;
    dynamic parsedAnswer;
    final saved = await showAdminFormSheet(
      context,
      title: item == null
          ? 'admin.contentLab.newQuestion'.tr()
          : 'admin.contentLab.editQuestion'.tr(),
      validate: () {
        if (prompt.text.trim().isEmpty) return false;
        try {
          final opts = options.text.trim().isEmpty
              ? <dynamic>[]
              : jsonDecode(options.text);
          if (opts is! List) return false;
          parsedOptions = opts;
          parsedAnswer = answer.text.trim().isEmpty
              ? null
              : jsonDecode(answer.text);
          return true;
        } catch (_) {
          return false;
        }
      },
      builder: (_) => [
        AppTextField(
          controller: prompt,
          label: 'admin.contentLab.prompt'.tr(),
          minLines: 2,
          maxLines: 4,
        ),
        StatefulBuilder(
          builder: (context, set) => Column(
            children: [
              _dropdown(
                'admin.contentLab.type'.tr(),
                type,
                _questionTypes,
                (v) => set(() => type = v),
              ),
              const SizedBox(height: AppSpacing.md),
              _dropdown(
                'admin.content.level'.tr(),
                level,
                vocabularyLevels,
                (v) => set(() => level = v),
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
        AppTextField(
          controller: options,
          label: 'admin.contentLab.options'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: answer,
          label: 'admin.contentLab.answer'.tr(),
          maxLines: 2,
        ),
        AppTextField(
          controller: explanation,
          label: 'admin.contentLab.explanation'.tr(),
          maxLines: 2,
        ),
        AppTextField(controller: tags, label: 'admin.content.tags'.tr()),
      ],
      onSubmit: () {
        final data = {
          'prompt': prompt.text.trim(),
          'question_type': type,
          'difficulty_level': level,
          'options': parsedOptions,
          'answer': parsedAnswer,
          'explanation': explanation.text.trim().isEmpty
              ? null
              : explanation.text.trim(),
          'tags': [
            for (final t in tags.text.split(','))
              if (t.trim().isNotEmpty) t.trim(),
          ],
          'is_active': active,
        };
        return item == null
            ? _repo.createQuestion(data)
            : _repo.updateQuestion(item.id, data);
      },
    );
    for (final c in [prompt, options, answer, explanation, tags]) {
      c.dispose();
    }
    if (saved) await _questions.controller.refresh();
  }

  Future<void> _editExam([TestExam? item]) async {
    final title = TextEditingController(text: item?.title);
    final description = TextEditingController(text: item?.description);
    final duration = TextEditingController(
      text: '${item?.durationMinutes ?? 20}',
    );
    final score = TextEditingController(text: '${item?.passingScore ?? 70}');
    var level = item?.level ?? 'A1';
    var published = item?.isPublished ?? false;
    final saved = await showAdminFormSheet(
      context,
      title: item == null
          ? 'admin.contentLab.newExam'.tr()
          : 'admin.contentLab.editExam'.tr(),
      validate: () {
        final d = int.tryParse(duration.text);
        final s = int.tryParse(score.text);
        return title.text.trim().isNotEmpty &&
            d != null &&
            d > 0 &&
            s != null &&
            s >= 0 &&
            s <= 100;
      },
      builder: (_) => [
        AppTextField(controller: title, label: 'admin.content.title'.tr()),
        AppTextField(
          controller: description,
          label: 'admin.content.description'.tr(),
          maxLines: 3,
        ),
        StatefulBuilder(
          builder: (context, set) => Column(
            children: [
              _dropdown(
                'admin.content.level'.tr(),
                level,
                vocabularyLevels,
                (v) => set(() => level = v),
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
        AppTextField(
          controller: duration,
          label: 'admin.contentLab.duration'.tr(),
          keyboardType: TextInputType.number,
        ),
        AppTextField(
          controller: score,
          label: 'admin.contentLab.passingScore'.tr(),
          keyboardType: TextInputType.number,
        ),
        if (item != null)
          Text(
            'admin.contentLab.questionsReadOnly'.tr(
              namedArgs: {'count': '${item.questionIds.length}'},
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
      ],
      onSubmit: () {
        final data = {
          'title': title.text.trim(),
          'description': description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          'level': level,
          'duration_minutes': int.parse(duration.text),
          'passing_score': int.parse(score.text),
          'is_published': published,
        };
        return item == null
            ? _repo.createTestExam(data)
            : _repo.updateTestExam(item.id, data);
      },
    );
    for (final c in [title, description, duration, score]) {
      c.dispose();
    }
    if (saved) await _exams.controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final permissions = context.watch<AdminPermissions>();
    final canCreate = permissions.can('content:create');
    final canUpdate = permissions.can('content:update');
    const header = Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.lg,
        AppSpacing.lg,
        0,
      ),
      child: AdminWebOnlyTile(),
    );
    return AdminPage(
      title: 'admin.nav.contentLab'.tr(),
      bottom: TabBar(
        controller: _tabs,
        tabs: [
          Tab(text: 'admin.contentLab.questions'.tr()),
          Tab(text: 'admin.contentLab.exams'.tr()),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _tabs.index == 0 ? _editQuestion() : _editExam(),
              icon: const Icon(Icons.add_rounded),
              label: Text('admin.content.create'.tr()),
            )
          : null,
      body: TabBarView(
        controller: _tabs,
        children: [
          AdminPagedList<QuestionItem>(
            pager: _questions,
            header: header,
            emptyTitle: 'admin.contentLab.noQuestions'.tr(),
            emptyIcon: Icons.help_outline_rounded,
            itemBuilder: (context, q, _) => AdminItemCard(
              title: q.prompt,
              subtitle: q.explanation,
              badges: [
                StatusPill(label: q.difficultyLevel, tone: StatusTone.info),
                StatusPill(label: q.questionType),
                if (!q.isActive)
                  StatusPill(
                    label: 'admin.content.inactive'.tr(),
                    tone: StatusTone.warning,
                  ),
              ],
              onTap: canUpdate ? () => _editQuestion(q) : null,
            ),
          ),
          AdminPagedList<TestExam>(
            pager: _exams,
            header: header,
            emptyTitle: 'admin.contentLab.noExams'.tr(),
            emptyIcon: Icons.assignment_outlined,
            itemBuilder: (context, e, _) => AdminItemCard(
              title: e.title,
              subtitle: 'admin.contentLab.examMeta'.tr(
                namedArgs: {
                  'minutes': '${e.durationMinutes}',
                  'count': '${e.questionIds.length}',
                },
              ),
              badges: [
                StatusPill(label: e.level, tone: StatusTone.info),
                StatusPill(
                  label: e.isPublished
                      ? 'admin.content.published'.tr()
                      : 'admin.content.draft'.tr(),
                  tone: e.isPublished ? StatusTone.success : StatusTone.neutral,
                ),
              ],
              onTap: canUpdate ? () => _editExam(e) : null,
            ),
          ),
        ],
      ),
    );
  }
}
