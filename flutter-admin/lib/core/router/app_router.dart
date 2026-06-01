import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/presentation/otp_screen.dart';
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
import '../../shared/widgets/admin_shell.dart';
import '../storage/token_storage.dart';

final _rootNavigatorKey = GlobalKey<NavigatorState>();
final _shellNavigatorKey = GlobalKey<NavigatorState>();

final appRouter = GoRouter(
  navigatorKey: _rootNavigatorKey,
  initialLocation: '/dashboard',
  redirect: (context, state) async {
    final hasToken = await TokenStorage.hasToken();
    final onAuth = state.matchedLocation.startsWith('/login') ||
        state.matchedLocation.startsWith('/otp');
    if (!hasToken && !onAuth) return '/login';
    if (hasToken && onAuth) return '/dashboard';
    return null;
  },
  routes: [
    GoRoute(
      path: '/login',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, __) => const LoginScreen(),
    ),
    GoRoute(
      path: '/otp',
      parentNavigatorKey: _rootNavigatorKey,
      builder: (_, state) {
        final email = state.extra as String? ?? '';
        return OtpScreen(email: email);
      },
    ),
    ShellRoute(
      navigatorKey: _shellNavigatorKey,
      builder: (context, state, child) => AdminShell(child: child),
      routes: [
        GoRoute(
          path: '/dashboard',
          builder: (_, __) => const DashboardScreen(),
        ),
        GoRoute(
          path: '/curriculum',
          builder: (_, __) => const CurriculumScreen(),
          routes: [
            GoRoute(
              path: 'course/:id',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, state) => CourseDetailScreen(
                courseId: state.pathParameters['id']!,
              ),
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
          path: '/users',
          builder: (_, __) => const UsersScreen(),
          routes: [
            GoRoute(
              path: ':id/stats',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, state) => UserStatsScreen(
                userId: state.pathParameters['id']!,
              ),
            ),
          ],
        ),
        GoRoute(
          path: '/settings',
          builder: (_, __) => const SettingsScreen(),
          routes: [
            GoRoute(
              path: 'analytics',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const AnalyticsScreen(),
            ),
            GoRoute(
              path: 'vocabulary',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const VocabularyScreen(),
            ),
            GoRoute(
              path: 'grammar',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const GrammarTestsScreen(),
            ),
            GoRoute(
              path: 'achievements',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const AchievementsShopScreen(),
            ),
            GoRoute(
              path: 'super-dashboard',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const SuperDashboardScreen(),
            ),
            GoRoute(
              path: 'system-health',
              parentNavigatorKey: _rootNavigatorKey,
              builder: (_, __) => const SystemHealthScreen(),
            ),
          ],
        ),
      ],
    ),
  ],
);
