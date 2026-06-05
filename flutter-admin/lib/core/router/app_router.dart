import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/auth_provider.dart';
import '../../features/dashboard/presentation/dashboard_screen.dart';
import '../../features/curriculum/presentation/curriculum_screen.dart';
import '../../features/curriculum/presentation/course_detail_screen.dart';
import '../../features/curriculum/presentation/units_lessons_screen.dart';
import '../../features/users/presentation/users_screen.dart';
import '../../features/users/presentation/user_stats_screen.dart';
import '../../features/settings/presentation/settings_screen.dart';
import '../../features/analytics/presentation/analytics_screen.dart';
import '../../features/vocabulary/presentation/vocabulary_screen.dart';
import '../../features/grammar/presentation/grammar_tests_screen.dart';
import '../../features/gamification/presentation/achievements_shop_screen.dart';
import '../../features/super_admin/presentation/super_dashboard_screen.dart';
import '../../features/super_admin/presentation/system_health_screen.dart';
import '../../features/super_admin/presentation/admin_management_screen.dart';
import '../../features/system_logs/presentation/logs_screen.dart';
import '../../features/ads/presentation/ads_screen.dart';
import '../../features/topics/presentation/topics_screen.dart';
import '../../features/system_settings/presentation/system_settings_screen.dart';
import '../../shared/widgets/admin_shell.dart';
import '../storage/token_storage.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

/// Routes accessible only to super admins.
const _superAdminPaths = ['/super/dashboard', '/super/admins'];

GoRouter createRouter(AuthProvider authProvider) {
  return GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/dashboard',
    refreshListenable: authProvider,
    redirect: (context, state) async {
      final hasToken = await TokenStorage.hasToken();
      final loc = state.matchedLocation;

      final onAuth = loc.startsWith('/login');

      if (!hasToken && !onAuth) return '/login';
      if (hasToken && onAuth) return '/dashboard';

      final onSuperAdmin = _superAdminPaths.any((p) => loc.startsWith(p));
      if (onSuperAdmin && hasToken && !authProvider.isSuperAdmin) {
        return '/dashboard';
      }

      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        parentNavigatorKey: _rootNavigatorKey,
        builder: (_, __) => const LoginScreen(),
      ),
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => AdminShell(child: child),
        routes: [
          // ── Overview ──────────────────────────────────────────────────────
          GoRoute(
            path: '/dashboard',
            builder: (_, __) => const DashboardScreen(),
          ),

          // ── Content ───────────────────────────────────────────────────────
          GoRoute(
            path: '/curriculum',
            builder: (_, __) => const CurriculumScreen(),
            routes: [
              GoRoute(
                path: 'course/:id',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) =>
                    CourseDetailScreen(courseId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: 'units',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) {
                  final args = state.extra as Map<String, dynamic>? ?? {};
                  return UnitsLessonsScreen(
                    unitId: args['unitId'] ?? '',
                    unitTitle: args['unitTitle'] ?? 'Unit',
                  );
                },
              ),
            ],
          ),
          GoRoute(
            path: '/topics',
            builder: (_, __) => const TopicsScreen(),
          ),
          GoRoute(
            path: '/vocabulary',
            builder: (_, __) => const VocabularyScreen(),
          ),
          GoRoute(
            path: '/grammar',
            builder: (_, __) => const GrammarTestsScreen(),
          ),
          GoRoute(
            path: '/analytics',
            builder: (_, __) => const AnalyticsScreen(),
          ),

          // ── Users ─────────────────────────────────────────────────────────
          GoRoute(
            path: '/users',
            builder: (_, __) => const UsersScreen(),
            routes: [
              GoRoute(
                path: ':id/stats',
                parentNavigatorKey: _rootNavigatorKey,
                builder: (_, state) =>
                    UserStatsScreen(userId: state.pathParameters['id']!),
              ),
            ],
          ),

          // ── Gamification ──────────────────────────────────────────────────
          GoRoute(
            path: '/achievements',
            builder: (_, __) => const AchievementsShopScreen(),
          ),

          // ── System ────────────────────────────────────────────────────────
          GoRoute(
            path: '/ads',
            builder: (_, __) => const AdsScreen(),
          ),
          GoRoute(
            path: '/logs',
            builder: (_, __) => const LogsScreen(),
          ),
          GoRoute(
            path: '/system-health',
            builder: (_, __) => const SystemHealthScreen(),
          ),
          GoRoute(
            path: '/system-settings',
            builder: (_, __) => const SystemSettingsScreen(),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, __) => const SettingsScreen(),
          ),

          // ── Super Admin ───────────────────────────────────────────────────
          GoRoute(
            path: '/super/dashboard',
            builder: (_, __) => const SuperDashboardScreen(),
          ),
          GoRoute(
            path: '/super/admins',
            builder: (_, __) => const AdminManagementScreen(),
          ),
        ],
      ),
    ],
  );
}
