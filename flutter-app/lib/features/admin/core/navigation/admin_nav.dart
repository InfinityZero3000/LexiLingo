import 'package:flutter/material.dart';

enum AdminNavGroup { overview, learners, content, growth, system, superAdmin }

/// One destination of the admin shell. A new screen is added here (and as a
/// route in `app_router.dart`); the drawer, the wide-screen sidebar and the
/// route guard all read this list.
class AdminNavItem {
  const AdminNavItem({
    required this.route,
    required this.labelKey,
    required this.icon,
    required this.activeIcon,
    required this.group,
    this.permission,
    this.superOnly = false,
  });

  final String route;
  final String labelKey;
  final IconData icon;
  final IconData activeIcon;
  final AdminNavGroup group;

  /// `resource:action` the role must hold, or null when any admin may open it.
  final String? permission;
  final bool superOnly;
}

extension AdminNavGroupLabel on AdminNavGroup {
  String get labelKey => 'admin.nav.group.$name';
}

const adminNavItems = <AdminNavItem>[
  AdminNavItem(
    route: '/dashboard',
    labelKey: 'admin.nav.dashboard',
    icon: Icons.dashboard_outlined,
    activeIcon: Icons.dashboard_rounded,
    group: AdminNavGroup.overview,
  ),
  AdminNavItem(
    route: '/users',
    labelKey: 'admin.nav.users',
    icon: Icons.group_outlined,
    activeIcon: Icons.group_rounded,
    group: AdminNavGroup.learners,
    permission: 'users:read',
  ),
  AdminNavItem(
    route: '/gem-ledger',
    labelKey: 'admin.nav.gemLedger',
    icon: Icons.diamond_outlined,
    activeIcon: Icons.diamond_rounded,
    group: AdminNavGroup.learners,
    permission: 'gifts:read',
  ),
  AdminNavItem(
    route: '/curriculum',
    labelKey: 'admin.nav.courses',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book_rounded,
    group: AdminNavGroup.content,
    permission: 'courses:read',
  ),
  AdminNavItem(
    route: '/categories',
    labelKey: 'admin.nav.categories',
    icon: Icons.category_outlined,
    activeIcon: Icons.category_rounded,
    group: AdminNavGroup.content,
    permission: 'categories:read',
  ),
  AdminNavItem(
    route: '/topics',
    labelKey: 'admin.nav.topics',
    icon: Icons.topic_outlined,
    activeIcon: Icons.topic_rounded,
    group: AdminNavGroup.content,
    permission: 'topics:read',
  ),
  AdminNavItem(
    route: '/vocabulary',
    labelKey: 'admin.nav.vocabulary',
    icon: Icons.book_outlined,
    activeIcon: Icons.book_rounded,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/grammar',
    labelKey: 'admin.nav.grammar',
    icon: Icons.quiz_outlined,
    activeIcon: Icons.quiz_rounded,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/content-lab',
    labelKey: 'admin.nav.contentLab',
    icon: Icons.science_outlined,
    activeIcon: Icons.science_rounded,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/ielts',
    labelKey: 'admin.nav.ielts',
    icon: Icons.school_outlined,
    activeIcon: Icons.school_rounded,
    group: AdminNavGroup.content,
    permission: 'ielts:read',
  ),
  AdminNavItem(
    route: '/content-qa',
    labelKey: 'admin.nav.contentQa',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check_rounded,
    group: AdminNavGroup.content,
    permission: 'content_agent:read',
  ),
  AdminNavItem(
    route: '/achievements',
    labelKey: 'admin.nav.achievements',
    icon: Icons.military_tech_outlined,
    activeIcon: Icons.military_tech_rounded,
    group: AdminNavGroup.growth,
    permission: 'achievements:read',
  ),
  AdminNavItem(
    route: '/ads',
    labelKey: 'admin.nav.ads',
    icon: Icons.campaign_outlined,
    activeIcon: Icons.campaign_rounded,
    group: AdminNavGroup.growth,
    permission: 'banners:read',
  ),
  AdminNavItem(
    route: '/notification-campaign',
    labelKey: 'admin.nav.campaigns',
    icon: Icons.notifications_active_outlined,
    activeIcon: Icons.notifications_active_rounded,
    group: AdminNavGroup.growth,
    permission: 'notifications:read',
  ),
  AdminNavItem(
    route: '/ranking-agent',
    labelKey: 'admin.nav.rankingAgent',
    icon: Icons.leaderboard_outlined,
    activeIcon: Icons.leaderboard_rounded,
    group: AdminNavGroup.growth,
    permission: 'ranking:read',
  ),
  AdminNavItem(
    route: '/analytics',
    labelKey: 'admin.nav.analytics',
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart_rounded,
    group: AdminNavGroup.system,
    permission: 'analytics:read',
  ),
  AdminNavItem(
    route: '/logs',
    labelKey: 'admin.nav.logs',
    icon: Icons.manage_search_outlined,
    activeIcon: Icons.manage_search_rounded,
    group: AdminNavGroup.system,
    permission: 'rbac:read',
  ),
  AdminNavItem(
    route: '/ops',
    labelKey: 'admin.nav.ops',
    icon: Icons.build_circle_outlined,
    activeIcon: Icons.build_circle_rounded,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/ai-quality',
    labelKey: 'admin.nav.aiQuality',
    icon: Icons.psychology_outlined,
    activeIcon: Icons.psychology_rounded,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/roles',
    labelKey: 'admin.nav.roles',
    icon: Icons.rule_outlined,
    activeIcon: Icons.rule_rounded,
    group: AdminNavGroup.system,
    permission: 'rbac:read',
  ),
  AdminNavItem(
    route: '/system-health',
    labelKey: 'admin.nav.health',
    icon: Icons.monitor_heart_outlined,
    activeIcon: Icons.monitor_heart_rounded,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/system-settings',
    labelKey: 'admin.nav.config',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune_rounded,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/settings',
    labelKey: 'admin.nav.settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings_rounded,
    group: AdminNavGroup.system,
  ),
  AdminNavItem(
    route: '/super/dashboard',
    labelKey: 'admin.nav.superDashboard',
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings_rounded,
    group: AdminNavGroup.superAdmin,
    superOnly: true,
  ),
  AdminNavItem(
    route: '/super/admins',
    labelKey: 'admin.nav.adminManagement',
    icon: Icons.manage_accounts_outlined,
    activeIcon: Icons.manage_accounts_rounded,
    group: AdminNavGroup.superAdmin,
    superOnly: true,
  ),
];

/// The nav item that guards [location] (a route or one of its sub-routes), or
/// null for a route that any signed-in admin may open.
AdminNavItem? adminNavItemFor(String location) {
  for (final item in adminNavItems) {
    if (location == item.route || location.startsWith('${item.route}/')) {
      return item;
    }
  }
  if (location.startsWith('/super')) {
    return adminNavItems.firstWhere((i) => i.superOnly);
  }
  return null;
}
