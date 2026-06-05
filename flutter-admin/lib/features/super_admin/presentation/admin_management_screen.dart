import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

class AdminManagementScreen extends StatefulWidget {
  const AdminManagementScreen({super.key});

  @override
  State<AdminManagementScreen> createState() => _AdminManagementScreenState();
}

class _AdminManagementScreenState extends State<AdminManagementScreen> {
  List<Map<String, dynamic>> _admins = [];
  bool _loading = true;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.instance.get('/admin/users', params: {
        'page': 1,
        'page_size': 50,
        'role': 'admin',
      });
      final data = resp['data'];
      final list = data is Map ? data['users'] ?? data['items'] ?? [] : data ?? [];
      if (mounted) {
        setState(() {
          _admins = List<Map<String, dynamic>>.from(list);
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> get _filtered {
    if (_search.isEmpty) return _admins;
    final q = _search.toLowerCase();
    return _admins.where((a) {
      final name = (a['display_name'] ?? a['username'] ?? '').toString().toLowerCase();
      final email = (a['email'] ?? '').toString().toLowerCase();
      return name.contains(q) || email.contains(q);
    }).toList();
  }

  int _roleLevel(Map<String, dynamic> admin) =>
      (admin['role_level'] as num?)?.toInt() ??
      (admin['role_slug'] == 'super_admin' ? 2 : 1);

  Future<void> _changeRole(Map<String, dynamic> admin, int newLevel) async {
    final id = admin['id']?.toString() ?? '';
    if (id.isEmpty) return;
    try {
      await ApiClient.instance.put('/admin/users/$id/role', data: {'role_level': newLevel});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e', style: GoogleFonts.spaceGrotesk())),
        );
      }
    }
  }

  Future<void> _toggleStatus(Map<String, dynamic> admin) async {
    final id = admin['id']?.toString() ?? '';
    final isActive = (admin['is_active'] as bool?) ?? true;
    if (id.isEmpty) return;
    try {
      await ApiClient.instance.put('/admin/users/$id/status', data: {'is_active': !isActive});
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed: $e', style: GoogleFonts.spaceGrotesk())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('Admin Management',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('SUPER ADMIN',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 9, fontWeight: FontWeight.w700,
                    color: Colors.white, letterSpacing: 0.5)),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (v) => setState(() => _search = v),
              style: GoogleFonts.spaceGrotesk(fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Search admins…',
                hintStyle: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted),
                prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.onSurfaceMuted),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Row(
              children: [
                _summaryChip(
                  icon: Icons.manage_accounts,
                  label: '${_admins.length} admins',
                  color: AppColors.primaryBright,
                ),
                const SizedBox(width: 8),
                _summaryChip(
                  icon: Icons.admin_panel_settings,
                  label: '${_admins.where((a) => _roleLevel(a) >= 2).length} super',
                  color: AppColors.primary,
                ),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : list.isEmpty
                    ? Center(
                        child: Text('No admins found',
                            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) => _AdminCard(
                          admin: list[i],
                          roleLevel: _roleLevel(list[i]),
                          onChangeRole: (lvl) => _changeRole(list[i], lvl),
                          onToggleStatus: () => _toggleStatus(list[i]),
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _summaryChip({required IconData icon, required String label, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
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
    final name = (admin['display_name'] ?? admin['username'] ?? 'Unknown').toString();
    final email = (admin['email'] ?? '').toString();
    final isActive = (admin['is_active'] as bool?) ?? true;
    final initials = name.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join();
    final isSuperAdmin = roleLevel >= 2;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outline, width: 0.5),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Stack(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: AppColors.primaryContainer,
                    child: Text(initials,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.primary)),
                  ),
                  if (!isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.black38,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.block, color: Colors.white, size: 14),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    Text(email,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, color: AppColors.onSurfaceMuted),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: isSuperAdmin ? AppColors.primary : AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(5),
                ),
                child: Text(
                  isSuperAdmin ? 'SUPER' : 'ADMIN',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      color: isSuperAdmin ? Colors.white : AppColors.primary,
                      letterSpacing: 0.4),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.outline),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  icon: isSuperAdmin ? Icons.arrow_downward : Icons.arrow_upward,
                  label: isSuperAdmin ? 'Demote' : 'Promote',
                  color: isSuperAdmin ? AppColors.warning : AppColors.success,
                  onTap: () => onChangeRole(isSuperAdmin ? 1 : 2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionButton(
                  icon: isActive ? Icons.block : Icons.check_circle_outline,
                  label: isActive ? 'Deactivate' : 'Activate',
                  color: isActive ? AppColors.error : AppColors.success,
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
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 6),
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600, color: color)),
            ],
          ),
        ),
      ),
    );
  }
}
