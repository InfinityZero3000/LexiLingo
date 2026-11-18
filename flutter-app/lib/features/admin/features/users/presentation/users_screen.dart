import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/debounced_search_field.dart';
import 'package:lexilingo_app/core/widgets/filter_chip_bar.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import '../../../shared/widgets/admin_paged_list_view.dart';
import '../../../shared/widgets/admin_screen_scaffold.dart';
import '../data/users_repository.dart';

/// Role filter values: -1 is "all", 0-2 are the backend's role levels.
const _anyRole = -1;
const _anyStatus = 'all';

String adminRoleLabelKey(int level) => switch (level) {
  2 => 'admin.users.roleSuper',
  1 => 'admin.users.roleAdmin',
  _ => 'admin.users.roleUser',
};

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key, this.repository});

  /// Replaces the real repository in tests.
  final UsersRepository? repository;

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  late final UsersRepository _repo = widget.repository ?? UsersRepository();
  late final AdminPageFetcher<AdminUserItem> _fetcher = AdminPageFetcher(
    _repo.listUsers,
  );
  late final PaginatedListController<AdminUserItem> _controller =
      PaginatedListController(fetcher: _fetcher);

  int _role = _anyRole;
  String _status = _anyStatus;
  UserSort _sort = UserSort.newest;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _controller.refresh();
  }

  @override
  void dispose() {
    _controller.dispose();
    _fetcher.total.dispose();
    super.dispose();
  }

  void _apply() => _controller.setFilters({
    if (_search.isNotEmpty) 'search': _search,
    if (_role != _anyRole) 'role': _role,
    if (_status != _anyStatus) 'is_active': _status == 'active',
    'sort': _sort,
  });

  String _sortLabel(UserSort sort) => switch (sort) {
    UserSort.newest => 'admin.users.sortNewest'.tr(),
    UserSort.recentLogin => 'admin.users.sortRecentLogin'.tr(),
    UserSort.topXp => 'admin.users.sortTopXp'.tr(),
    UserSort.email => 'admin.users.sortEmail'.tr(),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AdminScreenScaffold(
      title: 'admin.users.title'.tr(),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.sm,
              0,
            ),
            child: Row(
              children: [
                Expanded(
                  child: DebouncedSearchField(
                    hint: 'admin.users.searchHint'.tr(),
                    onChanged: (value) {
                      _search = value;
                      _apply();
                    },
                  ),
                ),
                PopupMenuButton<UserSort>(
                  tooltip: 'admin.users.sortBy'.tr(),
                  icon: const Icon(Icons.sort_rounded),
                  constraints: const BoxConstraints(minHeight: kMinTapTarget),
                  initialValue: _sort,
                  onSelected: (value) {
                    setState(() => _sort = value);
                    _apply();
                  },
                  itemBuilder: (_) => [
                    for (final sort in UserSort.values)
                      CheckedPopupMenuItem(
                        value: sort,
                        checked: sort == _sort,
                        child: Text(_sortLabel(sort)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterChipBar<int>(
            options: [
              FilterOption(
                value: _anyRole,
                label: 'admin.users.filterAllRoles'.tr(),
              ),
              for (final level in const [0, 1, 2])
                FilterOption(
                  value: level,
                  label: adminRoleLabelKey(level).tr(),
                ),
            ],
            selected: _role,
            onSelected: (value) {
              setState(() => _role = value ?? _anyRole);
              _apply();
            },
          ),
          FilterChipBar<String>(
            options: [
              FilterOption(
                value: _anyStatus,
                label: 'admin.users.filterAllStatus'.tr(),
              ),
              FilterOption(
                value: 'active',
                label: 'admin.users.statusActive'.tr(),
              ),
              FilterOption(
                value: 'inactive',
                label: 'admin.users.statusSuspended'.tr(),
              ),
            ],
            selected: _status,
            onSelected: (value) {
              setState(() => _status = value ?? _anyStatus);
              _apply();
            },
          ),
          ValueListenableBuilder<int?>(
            valueListenable: _fetcher.total,
            builder: (context, total, _) => total == null
                ? const SizedBox(height: AppSpacing.sm)
                : Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.xs,
                      AppSpacing.lg,
                      AppSpacing.xs,
                    ),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        'admin.users.total'.tr(namedArgs: {'count': '$total'}),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
          ),
          Expanded(
            child: AdminPagedListView<AdminUserItem>(
              controller: _controller,
              fetcher: _fetcher,
              emptyIcon: Icons.people_outline,
              emptyTitle: 'admin.users.emptyTitle'.tr(),
              emptyDescription: 'admin.users.emptyBody'.tr(),
              itemBuilder: (context, user, _) => UserTile(
                user: user,
                onTap: () => context.push('/users/${user.id}').then((_) {
                  if (mounted) _controller.refresh();
                }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class UserTile extends StatelessWidget {
  const UserTile({super.key, required this.user, required this.onTap});

  final AdminUserItem user;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final initial = user.shownName.isEmpty
        ? '?'
        : user.shownName.characters.first.toUpperCase();
    final avatar = user.avatarUrl?.trim();
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    return Material(
      color: scheme.surface,
      borderRadius: AppRadius.lgAll,
      child: InkWell(
        borderRadius: AppRadius.lgAll,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: scheme.primaryContainer,
                  foregroundColor: scheme.onPrimaryContainer,
                  foregroundImage: hasAvatar ? NetworkImage(avatar) : null,
                  onForegroundImageError: hasAvatar ? (_, __) {} : null,
                  child: Text(initial),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user.shownName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      Text(
                        user.email,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'admin.users.rowMeta'.tr(
                          namedArgs: {
                            'xp': '${user.totalXp}',
                            'streak': '${user.streakDays}',
                          },
                        ),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xs,
                        children: [
                          StatusPill(
                            label: user.isActive
                                ? 'admin.users.statusActive'.tr()
                                : 'admin.users.statusSuspended'.tr(),
                            tone: user.isActive
                                ? StatusTone.success
                                : StatusTone.neutral,
                          ),
                          if (user.roleLevel > 0)
                            StatusPill(
                              label: adminRoleLabelKey(user.roleLevel).tr(),
                              tone: StatusTone.info,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
