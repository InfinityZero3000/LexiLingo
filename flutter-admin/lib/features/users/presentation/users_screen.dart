import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../data/users_repository.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _repo = UsersRepository();
  List<AdminUserItem> _users = [];
  int _total = 0;
  bool _loading = true;
  final _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String? search]) async {
    setState(() => _loading = true);
    try {
      final result = await _repo.getUsers(search: search);
      if (mounted) {
        setState(() {
          _users = result['users'] as List<AdminUserItem>;
          _total = result['total'] as int;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
              onPressed: AdminShell.openDrawer,
            ),
            title: Row(
              children: [
                const Icon(Icons.language, color: AppColors.primary, size: 24),
                const SizedBox(width: 6),
                Text('LingoAdmin',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: AppColors.onSurface),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.onSurface),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'User Management',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Oversee LexiLingo's growing community of learners. Manage permissions, track progress.",
                  style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // Growth banner
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBright,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL GROWTH',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.08,
                                  color: Colors.white60)),
                          Text('+${_total > 0 ? '24' : '0'}%',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.03)),
                          Text('Since last month',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, color: Colors.white60)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search users by name, email, or language...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceMuted, size: 20),
                  ),
                  onSubmitted: _load,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.filter_list, size: 16),
                      label: Text('Filter',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: Text('Add User',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Users list table
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text('User',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Status',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Level',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        )
                      else if (_users.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('No users found',
                                style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _UserRow(
                            user: _users[i],
                            onTap: () => context.push('/users/${_users[i].id}/stats'),
                          ),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          'Showing ${_users.length} of ${_total > 0 ? _total : _users.length} users',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 12, color: AppColors.onSurfaceMuted),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatelessWidget {
  final AdminUserItem user;
  final VoidCallback onTap;

  const _UserRow({required this.user, required this.onTap});

  Color get _statusColor {
    switch (user.status) {
      case 'active':
        return AppColors.success;
      case 'blocked':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  Color get _statusBg {
    switch (user.status) {
      case 'active':
        return AppColors.successContainer;
      case 'blocked':
        return AppColors.errorContainer;
      default:
        return AppColors.warningContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primaryContainer,
                    backgroundImage: user.avatarUrl != null
                        ? NetworkImage(user.avatarUrl!)
                        : null,
                    child: user.avatarUrl == null
                        ? Text(
                            user.displayName.isNotEmpty
                                ? user.displayName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user.email,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11, color: AppColors.onSurfaceMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  user.statusDisplay,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                user.level,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
