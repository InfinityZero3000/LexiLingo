import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:provider/provider.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_item_card.dart';
import '../../../shared/widgets/admin_page.dart';
import '../../../shared/widgets/admin_paged_list.dart';
import '../../../shared/widgets/admin_web_only_tile.dart';
import '../data/ielts_repository.dart';

class IeltsScreen extends StatefulWidget {
  const IeltsScreen({super.key, this.repository});

  final IeltsRepository? repository;

  @override
  State<IeltsScreen> createState() => _IeltsScreenState();
}

class _IeltsScreenState extends State<IeltsScreen>
    with SingleTickerProviderStateMixin {
  late final IeltsRepository _repo = widget.repository ?? IeltsRepository();
  late final TabController _tabs = TabController(length: 2, vsync: this);
  late final AdminPager<IeltsTest> _tests = AdminPager(
    load: (request, _) => _repo.listTests(request),
  );
  late final AdminPager<IeltsAttempt> _attempts = AdminPager(
    pageSize: 100,
    load: (_, __) => _repo.listAttempts(),
  );

  @override
  void dispose() {
    _tabs.dispose();
    _tests.dispose();
    _attempts.dispose();
    super.dispose();
  }

  Future<void> _validate(IeltsTest test) async {
    final messenger = ScaffoldMessenger.of(context);
    IeltsValidation? result;
    String? failure;
    try {
      result = await _repo.validate(test.id);
    } catch (e) {
      failure = AdminApiError.from(e).message.resolve();
    }
    if (!mounted) return;
    if (result == null) {
      messenger.showSnackBar(SnackBar(content: Text(failure!)));
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ValidationSheet(test: test, result: result!),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canValidate = context.watch<AdminPermissions>().can('ielts:create');
    final dateFormat = intl.DateFormat.yMMMd().add_Hm();
    return AdminPage(
      title: 'admin.nav.ielts'.tr(),
      bottom: TabBar(
        controller: _tabs,
        tabs: [
          Tab(text: 'admin.ielts.tests'.tr()),
          Tab(text: 'admin.ielts.attempts'.tr()),
        ],
      ),
      body: TabBarView(
        controller: _tabs,
        children: [
          AdminPagedList<IeltsTest>(
            pager: _tests,
            emptyTitle: 'admin.ielts.noTests'.tr(),
            emptyIcon: Icons.school_outlined,
            header: const Padding(
              padding: EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                0,
              ),
              child: AdminWebOnlyTile(),
            ),
            itemBuilder: (context, t, _) => AdminItemCard(
              title: t.title,
              subtitle: 'admin.ielts.meta'.tr(
                namedArgs: {
                  'questions': '${t.questionCount}',
                  'attempts': '${t.attemptCount}',
                },
              ),
              badges: [
                StatusPill(label: t.skillScope, tone: StatusTone.info),
                if (t.targetBand != null) StatusPill(label: t.targetBand!),
                StatusPill(
                  label: t.isPublished
                      ? 'admin.content.published'.tr()
                      : 'admin.content.draft'.tr(),
                  tone: t.isPublished ? StatusTone.success : StatusTone.neutral,
                ),
              ],
              onTap: canValidate ? () => _validate(t) : null,
            ),
          ),
          AdminPagedList<IeltsAttempt>(
            pager: _attempts,
            emptyTitle: 'admin.ielts.noAttempts'.tr(),
            emptyIcon: Icons.history_rounded,
            itemBuilder: (context, a, _) => AdminItemCard(
              title: a.overallBand == null
                  ? 'admin.ielts.noBand'.tr()
                  : 'admin.ielts.band'.tr(
                      namedArgs: {'band': a.overallBand!.toStringAsFixed(1)},
                    ),
              subtitle: a.startedAt == null
                  ? null
                  : dateFormat.format(a.startedAt!.toLocal()),
              badges: [
                StatusPill(
                  label: a.status,
                  tone: a.submittedAt != null
                      ? StatusTone.success
                      : StatusTone.neutral,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ValidationSheet extends StatelessWidget {
  const _ValidationSheet({required this.test, required this.result});

  final IeltsTest test;
  final IeltsValidation result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(test.title, style: theme.textTheme.heading),
            const SizedBox(height: AppSpacing.md),
            StatusPill(
              label: result.publishable
                  ? 'admin.ielts.publishable'.tr()
                  : 'admin.ielts.blocked'.tr(),
              tone: result.publishable ? StatusTone.success : StatusTone.danger,
            ),
            const SizedBox(height: AppSpacing.lg),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final e in result.counts.entries)
                  StatusPill(label: '${e.key}: ${e.value}'),
              ],
            ),
            if (result.problems.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              Text(
                'admin.ielts.problems'.tr(),
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final p in result.problems)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    '• $p',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
