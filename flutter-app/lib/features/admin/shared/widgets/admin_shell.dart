import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
import '../../features/auth/data/auth_repository.dart';
import '../../features/auth/presentation/auth_provider.dart';

class AdminShell extends StatefulWidget {
  final Widget child;
  const AdminShell({super.key, required this.child});

  static final _scaffoldKey = GlobalKey<ScaffoldState>();
  static void openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final loc = GoRouterState.of(context).matchedLocation;

    return Scaffold(
      key: AdminShell._scaffoldKey,
      backgroundColor: AppColors.background,
      drawer: _AdminDrawer(auth: auth, currentLoc: loc),
      body: widget.child,
    );
  }
}

class _AdminDrawer extends StatelessWidget {
  final AuthProvider auth;
  final String currentLoc;

  const _AdminDrawer({required this.auth, required this.currentLoc});

  void _navigate(BuildContext context, String route) {
    Navigator.of(context).pop();
    context.go(route);
  }

  bool _isActive(String route) {
    if (route == '/dashboard') return currentLoc == '/dashboard' || currentLoc == '/';
    return currentLoc.startsWith(route);
  }

  @override
  Widget build(BuildContext context) {
    final user = auth.user;
    return Drawer(
      backgroundColor: AppColors.surface,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(user),
            const Divider(height: 1, color: AppColors.outline),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 8),
                children: [
                  _section('OVERVIEW'),
                  _item(context, icon: Icons.dashboard_outlined, activeIcon: Icons.dashboard, label: 'Dashboard', route: '/dashboard'),
                  _section('CONTENT'),
                  _item(context, icon: Icons.menu_book_outlined, activeIcon: Icons.menu_book, label: 'Courses', route: '/curriculum'),
                  _item(context, icon: Icons.topic_outlined, activeIcon: Icons.topic, label: 'Topics', route: '/topics'),
                  _item(context, icon: Icons.book_outlined, activeIcon: Icons.book, label: 'Vocabulary', route: '/vocabulary'),
                  _item(context, icon: Icons.quiz_outlined, activeIcon: Icons.quiz, label: 'Grammar & Tests', route: '/grammar'),
                  _item(context, icon: Icons.science_outlined, activeIcon: Icons.science, label: 'Content Lab', route: '/content-lab'),
                  _item(context, icon: Icons.bar_chart_outlined, activeIcon: Icons.bar_chart, label: 'Analytics', route: '/analytics'),
                  _section('USERS'),
                  _item(context, icon: Icons.group_outlined, activeIcon: Icons.group, label: 'User Management', route: '/users'),
                  _section('GAMIFICATION'),
                  _item(context, icon: Icons.military_tech_outlined, activeIcon: Icons.military_tech, label: 'Achievements & Shop', route: '/achievements'),
                  _section('AUTOMATION'),
                  _item(context, icon: Icons.fact_check_outlined, activeIcon: Icons.fact_check, label: 'Content QA Queue', route: '/content-qa'),
                  _item(context, icon: Icons.notifications_active_outlined, activeIcon: Icons.notifications_active, label: 'Notification Campaigns', route: '/notification-campaign'),
                  _item(context, icon: Icons.leaderboard_outlined, activeIcon: Icons.leaderboard, label: 'Ranking Agent', route: '/ranking-agent'),
                  _section('SYSTEM'),
                  _item(context, icon: Icons.campaign_outlined, activeIcon: Icons.campaign, label: 'Banner Ads', route: '/ads'),
                  _item(context, icon: Icons.manage_search_outlined, activeIcon: Icons.manage_search, label: 'Audit Logs', route: '/logs'),
                  _item(context, icon: Icons.monitor_heart_outlined, activeIcon: Icons.monitor_heart, label: 'System Health', route: '/system-health'),
                  _item(context, icon: Icons.tune_outlined, activeIcon: Icons.tune, label: 'System Config', route: '/system-settings'),
                  _item(context, icon: Icons.settings_outlined, activeIcon: Icons.settings, label: 'Settings', route: '/settings'),
                  if (auth.isSuperAdmin) ...[
                    _section('SUPER ADMIN'),
                    _item(context, icon: Icons.admin_panel_settings_outlined, activeIcon: Icons.admin_panel_settings, label: 'Super Dashboard', route: '/super/dashboard'),
                    _item(context, icon: Icons.manage_accounts_outlined, activeIcon: Icons.manage_accounts, label: 'Admin Management', route: '/super/admins'),
                  ],
                  const SizedBox(height: 8),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.outline),
            _buildLogout(context),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(AdminUser? user) {
    final initials = (user?.displayName.isNotEmpty == true)
        ? user!.displayName.split(' ').take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join()
        : 'A';

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.primary, width: 2),
            ),
            child: ClipOval(
              child: user?.avatarUrl != null
                  ? Image.network(user!.avatarUrl!, fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _initialsAvatar(initials))
                  : _initialsAvatar(initials),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(user?.displayName ?? 'Admin',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                Text(user?.email ?? '',
                    style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.onSurfaceMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: auth.isSuperAdmin ? AppColors.primary : AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    auth.isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        color: auth.isSuperAdmin ? Colors.white : AppColors.primary,
                        letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _initialsAvatar(String initials) => Container(
        color: AppColors.primaryContainer,
        alignment: Alignment.center,
        child: Text(initials,
            style: GoogleFonts.spaceGrotesk(
                color: AppColors.primary, fontWeight: FontWeight.w700, fontSize: 14)),
      );

  Widget _section(String label) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
        child: Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted, letterSpacing: 0.8)),
      );

  Widget _item(BuildContext context,
      {required IconData icon,
      required IconData activeIcon,
      required String label,
      required String route}) {
    final active = _isActive(route);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 1),
      child: Material(
        color: active ? const Color(0x1AFF4D00) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          onTap: () => _navigate(context, route),
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                Icon(active ? activeIcon : icon, size: 18,
                    color: active ? AppColors.primaryBright : AppColors.onSurfaceMuted),
                const SizedBox(width: 10),
                Text(label,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        color: active ? AppColors.primaryBright : AppColors.onSurface)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLogout(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: () async {
              Navigator.of(context).pop();
              await auth.logout();
              if (context.mounted) context.go('/login');
            },
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  const Icon(Icons.logout_rounded, size: 17, color: AppColors.error),
                  const SizedBox(width: 10),
                  Text('Logout',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.error)),
                ],
              ),
            ),
          ),
        ),
      );
}
