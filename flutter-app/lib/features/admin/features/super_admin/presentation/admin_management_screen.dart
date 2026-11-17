import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final responses = await Future.wait([
        ApiClient.instance.get(
          ApiEndpoints.adminUsers,
          params: {'page': 1, 'page_size': 100, 'role': 1},
        ),
        ApiClient.instance.get(
          ApiEndpoints.adminUsers,
          params: {'page': 1, 'page_size': 100, 'role': 2},
        ),
      ]);
      final list = responses.expand((resp) {
        final data = resp['data'];
        return data is Map ? data['users'] ?? data['items'] ?? [] : data ?? [];
      }).toList();
      if (mounted) {
        setState(() {
          _admins = List<Map<String, dynamic>>.from(list);
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load admins.';
          _loading = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _admins;
    final q = _search.toLowerCase();
    return _admins.where((a) {
      final name = (a['display_name'] ?? a['username'] ?? '')
          .toString()
          .toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  int _roleLevel(Map<String, dynamic> admin) =>
      (admin['role_level'] as num?)?.toInt() ??
      (admin['role_slug'] == 'super_admin' ? 2 : 1);

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _changeRole(Map<String, dynamic> admin, int newLevel) async {
    final id = admin['id']?.toString() ?? '';
    if (id.isEmpty) return;
    final name = admin['display_name'] ?? admin['email'] ?? 'this admin';
    final label = newLevel == 2 ? 'Super Admin' : 'Admin';
    final ok = await _confirm('Change role?', 'Set $name\'s role to $label?');
    if (!ok) return;
    try {
      await ApiClient.instance.put(
        '${ApiEndpoints.adminUsers}/$id/role',
        data: {'level': newLevel},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not change role.',
              style: GoogleFonts.spaceGrotesk(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> admin) async {
    final id = admin['id']?.toString() ?? '';
    final isActive = (admin['is_active'] as bool?) ?? true;
    if (id.isEmpty) return;
    final name = admin['display_name'] ?? admin['email'] ?? 'this admin';
    final ok = await _confirm(
      isActive ? 'Deactivate account?' : 'Activate account?',
      isActive
          ? 'Deactivate $name\'s account? They will not be able to sign in until reactivated.'
          : 'Reactivate $name\'s account?',
    );
    if (!ok) return;
    try {
      await ApiClient.instance.put(
        '${ApiEndpoints.adminUsers}/$id/status',
        data: {'is_active': !isActive},
      );
      await _load();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Could not update status.',
              style: GoogleFonts.spaceGrotesk(),
            ),
          ),
        );
      }
    }
  }

  Future<void> _showAddAdmin() async {
    final emailController = TextEditingController();
    var roleLevel = 1;
    var adding = false;
    String? dialogError;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(
            'Add Admin',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailController,
                keyboardType: TextInputType.emailAddress,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Existing user email',
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              DropdownButtonFormField<int>(
                initialValue: roleLevel,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 1, child: Text('Admin')),
                  DropdownMenuItem(value: 2, child: Text('Super Admin')),
                ],
                onChanged: adding ? null : (value) => roleLevel = value ?? 1,
              ),
              if (dialogError != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  dialogError!,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AdminColors.error),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: adding ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            SizedBox(
              height: 44,
              child: FilledButton(
                onPressed: adding
                    ? null
                    : () async {
                        final email = emailController.text.trim();
                        if (email.isEmpty) return;
                        setDialogState(() {
                          adding = true;
                          dialogError = null;
                        });
                        try {
                          final response = await ApiClient.instance.get(
                            ApiEndpoints.adminUsers,
                            params: {'search': email, 'page_size': 10},
                          );
                          final data = response['data'];
                          final users = data is Map
                              ? data['users'] as List? ?? []
                              : const [];
                          Map? target;
                          for (final user in users.cast<Map>()) {
                            if (user['email']?.toString().toLowerCase() ==
                                email.toLowerCase()) {
                              target = user;
                              break;
                            }
                          }
                          if (target == null) {
                            throw Exception(
                              'User not found. They must register first.',
                            );
                          }
                          await ApiClient.instance.put(
                            '${ApiEndpoints.adminUsers}/${target['id']}/role',
                            data: {'level': roleLevel},
                          );
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          await _load();
                        } catch (e) {
                          final message = e.toString().startsWith('Exception: ')
                              ? e.toString().replaceFirst('Exception: ', '')
                              : 'Could not add admin.';
                          if (dialogContext.mounted) {
                            setDialogState(() {
                              dialogError = message;
                              adding = false;
                            });
                          }
                        }
                      },
                child: adding
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Add'),
              ),
            ),
          ],
        ),
      ),
    );
    emailController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: AdminColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AdminColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text(
          'Admin Management',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: 4,
            ),
            decoration: BoxDecoration(
              color: AdminColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'SUPER ADMIN',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: Theme.of(context).colorScheme.onPrimary,
                letterSpacing: 0.5,
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddAdmin,
        icon: const Icon(Icons.person_add_alt_1),
        label: Text(
          'Add Admin',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: Theme.of(context).textTheme.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search admins…',
                hintStyle: GoogleFonts.spaceGrotesk(
                  color: AdminColors.onSurfaceMuted,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  size: 18,
                  color: AdminColors.onSurfaceMuted,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          // Summary row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _summaryChip(
                  icon: Icons.manage_accounts,
                  label: '${_admins.length} admins',
                  color: AdminColors.primaryBright,
                ),
                const SizedBox(width: AppSpacing.sm),
                _summaryChip(
                  icon: Icons.admin_panel_settings,
                  label:
                      '${_admins.where((a) => _roleLevel(a) >= 2).length} super',
                  color: AdminColors.primary,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: SkeletonBox(height: 220, borderRadius: 16),
                  )
                : _error != null
                ? _ErrorState(message: _error!, onRetry: _load)
                : list.isEmpty
                ? Center(
                    child: Text(
                      'No admins found',
                      style: GoogleFonts.spaceGrotesk(
                        color: AdminColors.onSurfaceMuted,
                      ),
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: list.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (ctx, i) => _AdminCard(
                        admin: list[i],
                        roleLevel: _roleLevel(list[i]),
                        onChangeRole: (lvl) => _changeRole(list[i], lvl),
                        onToggleStatus: () => _toggleStatus(list[i]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({
    required IconData icon,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _AdminCard extends StatelessWidget {
  final Map<String, dynamic> admin;
  final int roleLevel;
  final ValueChanged<int> onChangeRole;
  final VoidCallback onToggleStatus;

  const _AdminCard({
    required this.admin,
    required this.roleLevel,
    required this.onChangeRole,
    required this.onToggleStatus,
  });

  @override
  Widget build(BuildContext context) {
    final name = (admin['display_name'] ?? admin['username'] ?? 'Unknown')
        .toString();
    final email = (admin['email'] ?? '').toString();
    final isActive = (admin['is_active'] as bool?) ?? true;
    final provider = admin['provider'] is List
        ? (admin['provider'] as List).join(', ')
        : (admin['provider'] ?? '—').toString();
    final lastLogin = (admin['last_login'] ?? '').toString();
    final initials = name
        .split(' ')
        .take(2)
        .map((w) => w.isNotEmpty ? w[0].toUpperCase() : '')
        .join();
    final isSuperAdmin = roleLevel >= 2;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AdminColors.outline, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AdminColors.primaryContainer,
                    child: Text(
                      initials,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AdminColors.primary,
                      ),
                    ),
                  ),
                  if (!isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.scrim.withValues(alpha: 0.38),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.block,
                          color: Theme.of(context).colorScheme.onPrimary,
                          size: 14,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AdminColors.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      email,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AdminColors.onSurfaceMuted,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSuperAdmin
                      ? AdminColors.primary
                      : AdminColors.primaryContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isSuperAdmin ? 'SUPER' : 'ADMIN',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isSuperAdmin
                        ? Theme.of(context).colorScheme.onPrimary
                        : AdminColors.primary,
                    letterSpacing: 0.4,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              const Icon(
                Icons.login,
                size: 14,
                color: AdminColors.onSurfaceMuted,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  lastLogin.isEmpty
                      ? 'Never signed in'
                      : 'Last login ${lastLogin.split('T').first}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: AdminColors.onSurfaceMuted,
                  ),
                ),
              ),
              Text(
                provider,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AdminColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          const Divider(height: 1, color: AdminColors.outline),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: isSuperAdmin
                      ? Icons.arrow_downward
                      : Icons.arrow_upward,
                  label: isSuperAdmin ? 'Demote' : 'Promote',
                  color: isSuperAdmin
                      ? AdminColors.warning
                      : AdminColors.success,
                  onTap: () => onChangeRole(isSuperAdmin ? 1 : 2),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: _ActionButton(
                  icon: isActive ? Icons.block : Icons.check_circle_outline,
                  label: isActive ? 'Deactivate' : 'Activate',
                  color: isActive ? AdminColors.error : AdminColors.success,
                  onTap: onToggleStatus,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 13),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AdminColors.error, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Could not load admins',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    ),
  );
}
