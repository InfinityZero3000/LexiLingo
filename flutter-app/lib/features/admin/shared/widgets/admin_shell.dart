import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import '../../core/navigation/admin_nav.dart';
import '../../core/permissions/admin_permissions.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../admin_exit_scope.dart';
import 'admin_theme_toggle.dart';

/// Width from which the navigation is a fixed sidebar instead of a drawer.
const adminWideBreakpoint = 768.0;

/// Frame around every admin screen: a drawer on phones, a sidebar from
/// [adminWideBreakpoint]. Navigation comes from [adminNavItems], filtered by
/// the role and the permissions the backend reported.
class AdminShell extends StatelessWidget {
  const AdminShell({super.key, required this.child});

  final Widget child;

  static final _scaffoldKey = GlobalKey<ScaffoldState>();

  /// Screens call this from their menu button; it does nothing on wide layouts,
  /// where the sidebar is always there.
  static void openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final permissions = context.watch<AdminPermissions>();
    final location = GoRouterState.of(context).matchedLocation;
    final wide = MediaQuery.sizeOf(context).width >= adminWideBreakpoint;

    final nav = _AdminNav(
      auth: auth,
      permissions: permissions,
      location: location,
      onNavigate: (route) {
        if (!wide) Navigator.of(context).pop();
        context.go(route);
      },
    );

    return Scaffold(
      key: _scaffoldKey,
      drawer: wide ? null : Drawer(child: SafeArea(child: nav)),
      body: wide
          ? Row(
              children: [
                SizedBox(
                  width: 264,
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: SafeArea(child: nav),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  color: Theme.of(context).colorScheme.outlineVariant,
                ),
                Expanded(child: child),
              ],
            )
          : child,
    );
  }
}

class _AdminNav extends StatelessWidget {
  const _AdminNav({
    required this.auth,
    required this.permissions,
    required this.location,
    required this.onNavigate,
  });

  final AuthProvider auth;
  final AdminPermissions permissions;
  final String location;
  final ValueChanged<String> onNavigate;

  bool _visible(AdminNavItem item) {
    if (item.superOnly) return auth.isSuperAdmin;
    final required = item.permission;
    if (required == null) return true;
    return permissions.isReady && permissions.can(required);
  }

  bool _isActive(String route) {
    if (route == '/dashboard') {
      return location == '/dashboard' || location == '/';
    }
    return location == route || location.startsWith('$route/');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final items = adminNavItems.where(_visible).toList();

    return Column(
      children: [
        _Header(auth: auth),
        Divider(height: 1, color: scheme.outlineVariant),
        if (permissions.status == AdminPermissionsStatus.failed)
          _PermissionsBanner(onRetry: permissions.load),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            children: [
              for (final group in AdminNavGroup.values)
                if (items.any((i) => i.group == group)) ...[
                  _GroupLabel(group.labelKey.tr()),
                  for (final item in items.where((i) => i.group == group))
                    _NavTile(
                      item: item,
                      active: _isActive(item.route),
                      onTap: () => onNavigate(item.route),
                    ),
                ],
            ],
          ),
        ),
        Divider(height: 1, color: scheme.outlineVariant),
        const AdminThemeModeSelector(),
        const _ExitTile(),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.auth});

  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final AdminUser? user = auth.user;
    final name = user?.displayName ?? '';

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          AdminUserAvatar(
            avatarUrl: user?.avatarUrl,
            displayName: name,
            radius: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name.isEmpty ? 'Admin' : name,
                  style: theme.textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  user?.email ?? '',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: auth.isSuperAdmin
                        ? scheme.primary
                        : scheme.primaryContainer,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    (auth.isSuperAdmin
                            ? 'admin.shell.roleSuper'
                            : 'admin.shell.roleAdmin')
                        .tr(),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: auth.isSuperAdmin
                          ? scheme.onPrimary
                          : scheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xl,
        AppSpacing.md,
        AppSpacing.xl,
        AppSpacing.xs,
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.active,
    required this.onTap,
  });

  final AdminNavItem item;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final color = active ? scheme.primary : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Material(
        color: active
            ? scheme.primary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: AppRadius.mdAll,
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.mdAll,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kMinTapTarget),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: active
                          ? scheme.primary.withValues(alpha: 0.14)
                          : scheme.surfaceContainer,
                      borderRadius: AppRadius.smAll,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      active ? item.activeIcon : item.icon,
                      size: 17,
                      color: active ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      item.labelKey.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: color,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PermissionsBanner extends StatelessWidget {
  const _PermissionsBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final status = context.status;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.all(AppSpacing.sm),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: status.warningContainer,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'admin.shell.permissionsFailed'.tr(),
              style: theme.textTheme.bodySmall?.copyWith(
                color: status.onWarningContainer,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text('common.retry'.tr())),
        ],
      ),
    );
  }
}

class _ExitTile extends StatelessWidget {
  const _ExitTile();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: InkWell(
        borderRadius: AppRadius.mdAll,
        onTap: () {
          final exit = AdminExitScope.maybeOf(context)?.onExit;
          final scaffold = Scaffold.maybeOf(context);
          if (scaffold != null && scaffold.isDrawerOpen) {
            Navigator.of(context).pop();
          }
          exit?.call();
        },
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
            child: Row(
              children: [
                Icon(Icons.exit_to_app_rounded, size: 20, color: color),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    'admin.shell.exit'.tr(),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
