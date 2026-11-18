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
    activeIcon: Icons.dashboard,
    group: AdminNavGroup.overview,
  ),
  AdminNavItem(
    route: '/users',
    labelKey: 'admin.nav.users',
    icon: Icons.group_outlined,
    activeIcon: Icons.group,
    group: AdminNavGroup.learners,
    permission: 'users:read',
  ),
  AdminNavItem(
    route: '/curriculum',
    labelKey: 'admin.nav.courses',
    icon: Icons.menu_book_outlined,
    activeIcon: Icons.menu_book,
    group: AdminNavGroup.content,
    permission: 'courses:read',
  ),
  AdminNavItem(
    route: '/categories',
    labelKey: 'admin.nav.categories',
    icon: Icons.category_outlined,
    activeIcon: Icons.category,
    group: AdminNavGroup.content,
    permission: 'categories:read',
  ),
  AdminNavItem(
    route: '/topics',
    labelKey: 'admin.nav.topics',
    icon: Icons.topic_outlined,
    activeIcon: Icons.topic,
    group: AdminNavGroup.content,
    permission: 'topics:read',
  ),
  AdminNavItem(
    route: '/vocabulary',
    labelKey: 'admin.nav.vocabulary',
    icon: Icons.book_outlined,
    activeIcon: Icons.book,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/grammar',
    labelKey: 'admin.nav.grammar',
    icon: Icons.quiz_outlined,
    activeIcon: Icons.quiz,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/content-lab',
    labelKey: 'admin.nav.contentLab',
    icon: Icons.science_outlined,
    activeIcon: Icons.science,
    group: AdminNavGroup.content,
    permission: 'content:read',
  ),
  AdminNavItem(
    route: '/ielts',
    labelKey: 'admin.nav.ielts',
    icon: Icons.school_outlined,
    activeIcon: Icons.school,
    group: AdminNavGroup.content,
    permission: 'ielts:read',
  ),
  AdminNavItem(
    route: '/content-qa',
    labelKey: 'admin.nav.contentQa',
    icon: Icons.fact_check_outlined,
    activeIcon: Icons.fact_check,
    group: AdminNavGroup.content,
    permission: 'content_agent:read',
  ),
  AdminNavItem(
    route: '/achievements',
    labelKey: 'admin.nav.achievements',
    icon: Icons.military_tech_outlined,
    activeIcon: Icons.military_tech,
    group: AdminNavGroup.growth,
    permission: 'achievements:read',
  ),
  AdminNavItem(
    route: '/ads',
    labelKey: 'admin.nav.ads',
    icon: Icons.campaign_outlined,
    activeIcon: Icons.campaign,
    group: AdminNavGroup.growth,
    permission: 'banners:read',
  ),
  AdminNavItem(
    route: '/notification-campaign',
    labelKey: 'admin.nav.campaigns',
    icon: Icons.notifications_active_outlined,
    activeIcon: Icons.notifications_active,
    group: AdminNavGroup.growth,
    permission: 'notifications:read',
  ),
  AdminNavItem(
    route: '/ranking-agent',
    labelKey: 'admin.nav.rankingAgent',
    icon: Icons.leaderboard_outlined,
    activeIcon: Icons.leaderboard,
    group: AdminNavGroup.growth,
    permission: 'ranking:read',
  ),
  AdminNavItem(
    route: '/analytics',
    labelKey: 'admin.nav.analytics',
    icon: Icons.bar_chart_outlined,
    activeIcon: Icons.bar_chart,
    group: AdminNavGroup.system,
    permission: 'analytics:read',
  ),
  AdminNavItem(
    route: '/logs',
    labelKey: 'admin.nav.logs',
    icon: Icons.manage_search_outlined,
    activeIcon: Icons.manage_search,
    group: AdminNavGroup.system,
    permission: 'rbac:read',
  ),
  AdminNavItem(
    route: '/ops',
    labelKey: 'admin.nav.ops',
    icon: Icons.build_circle_outlined,
    activeIcon: Icons.build_circle,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/ai-quality',
    labelKey: 'admin.nav.aiQuality',
    icon: Icons.psychology_outlined,
    activeIcon: Icons.psychology,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/roles',
    labelKey: 'admin.nav.roles',
    icon: Icons.rule_outlined,
    activeIcon: Icons.rule,
    group: AdminNavGroup.system,
    permission: 'rbac:read',
  ),
  AdminNavItem(
    route: '/system-health',
    labelKey: 'admin.nav.health',
    icon: Icons.monitor_heart_outlined,
    activeIcon: Icons.monitor_heart,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/system-settings',
    labelKey: 'admin.nav.config',
    icon: Icons.tune_outlined,
    activeIcon: Icons.tune,
    group: AdminNavGroup.system,
    permission: 'ops:read',
  ),
  AdminNavItem(
    route: '/settings',
    labelKey: 'admin.nav.settings',
    icon: Icons.settings_outlined,
    activeIcon: Icons.settings,
    group: AdminNavGroup.system,
  ),
  AdminNavItem(
    route: '/super/dashboard',
    labelKey: 'admin.nav.superDashboard',
    icon: Icons.admin_panel_settings_outlined,
    activeIcon: Icons.admin_panel_settings,
    group: AdminNavGroup.superAdmin,
    superOnly: true,
  ),
  AdminNavItem(
    route: '/super/admins',
    labelKey: 'admin.nav.adminManagement',
    icon: Icons.manage_accounts_outlined,
    activeIcon: Icons.manage_accounts,
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
