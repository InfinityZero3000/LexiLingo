import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';
import 'package:lexilingo_app/features/admin/features/analytics/presentation/analytics_screen.dart';
import 'package:lexilingo_app/features/admin/features/super_admin/presentation/admin_management_screen.dart';
import 'package:lexilingo_app/features/admin/features/super_admin/presentation/system_health_screen.dart';
import 'package:lexilingo_app/features/admin/features/system/data/system_models.dart';
import 'package:lexilingo_app/features/admin/features/system/data/system_repository.dart';
import 'package:lexilingo_app/features/admin/features/system/presentation/screens/ops_center_screen.dart';
import 'package:lexilingo_app/features/admin/features/system/presentation/screens/roles_screen.dart';
import 'package:lexilingo_app/features/admin/features/system_logs/data/logs_repository.dart';
import 'package:lexilingo_app/features/admin/features/system_logs/presentation/logs_screen.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/features/admin/shared/widgets/admin_async_body.dart';

class _RecordingRepo extends _Repo {
  final opsCalls = <String>[];

  @override
  Future<JsonSnapshot> ops(String name, {int? days}) {
    opsCalls.add(name);
    return super.ops(name, days: days);
  }
}

class _Repo implements SystemRepository {
  _Repo({this.fail});
  final Object? fail;

  Future<T> _r<T>(T value) async {
    if (fail != null) throw fail!;
    return value;
  }

  @override
  Future<JsonSnapshot> ops(String name, {int? days}) => _r(
    JsonSnapshot.from({
      'queued': 3,
      'workers': [
        {'name': 'w1', 'state': 'up'},
      ],
    }),
  );
  @override
  Future<JsonSnapshot> monitoring(String name) =>
      _r(JsonSnapshot.from({'percent': 40}));
  @override
  Future<JsonSnapshot> integrations() => _r(JsonSnapshot.from({'redis': 'up'}));
  @override
  Future<JsonSnapshot> kpis() => _r(JsonSnapshot.from({'total_users': 1500}));
  @override
  Future<List<CoursePopularity>> coursePopularity() =>
      _r([const CoursePopularity(title: 'IELTS', enrollments: 10)]);
  @override
  Future<JsonSnapshot> contentPerformance() => _r(JsonSnapshot.from({}));
  @override
  Future<JsonSnapshot> vocabularyEffectiveness() => _r(JsonSnapshot.from({}));
  @override
  Future<JsonSnapshot> completionFunnel() => _r(JsonSnapshot.from({}));
  @override
  Future<List<FunnelStep>> activationFunnel() =>
      _r([const FunnelStep(key: 'a', label: 'Signed up', count: 9)]);
  @override
  Future<List<RoleSummary>> roles() =>
      _r([const RoleSummary(slug: 'admin', name: 'Admin', isSystem: true)]);
  @override
  Future<RolePermissions> rolePermissions(String slug) => _r(
    const RolePermissions({
      'users': ['read', 'update'],
    }),
  );
  @override
  Future<List<Map<String, dynamic>>> admins() => _r([
    {'email': 'a@b.c', 'full_name': 'Ada', 'role_level': 2},
  ]);
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Logs implements LogsRepository {
  _Logs({this.empty = false, this.facetError});
  final bool empty;
  final Object? facetError;

  @override
  Future<PageResult<AuditLogEntry>> fetchPage(
    PageRequest request,
    Map<String, Object?> filters,
  ) async => PageResult(
    items: empty
        ? []
        : [
            AuditLogEntry(
              createdAt: 'now',
              action: 'login',
              resourceType: 'user',
            ),
          ],
    total: empty ? 0 : 1,
  );

  @override
  Future<AuditFacets> facets() async {
    if (facetError != null) throw facetError!;
    return const AuditFacets(actions: ['login'], resourceTypes: ['user']);
  }
}

DioException _status(int code) => DioException(
  requestOptions: RequestOptions(path: '/x'),
  response: Response(
    requestOptions: RequestOptions(path: '/x'),
    statusCode: code,
    data: {'detail': 'nope'},
  ),
  type: DioExceptionType.badResponse,
);

Future<void> _pump(WidgetTester tester, Widget screen, {Size? size}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size ?? const Size(390, 800);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  await tester.pumpWidget(MaterialApp(home: screen));
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() => dotenv.loadFromString(isOptional: true));

  group('AdminAsyncBody', () {
    testWidgets('shows data', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: AdminAsyncBody<int>(
            load: () async => 7,
            builder: (_, v) => Text('value $v'),
          ),
        ),
      );
      expect(find.text('value 7'), findsOneWidget);
    });

    testWidgets('403 is a no-access state', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: AdminAsyncBody<int>(
            load: () => Future.error(_status(403)),
            builder: (_, v) => Text('value $v'),
          ),
        ),
      );
      expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
    });

    testWidgets('503 reads as turned off', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: AdminAsyncBody<int>(
            load: () => Future.error(_status(503)),
            builder: (_, v) => Text('$v'),
          ),
        ),
      );
      expect(find.text('admin.access.featureOffTitle'), findsOneWidget);
    });

    testWidgets('a 500 offers retry', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: AdminAsyncBody<int>(
            load: () => Future.error(_status(500)),
            builder: (_, v) => Text('$v'),
          ),
        ),
      );
      expect(find.byType(ErrorDisplayWidget), findsOneWidget);
    });

    testWidgets('empty uses the empty widget', (tester) async {
      await _pump(
        tester,
        Scaffold(
          body: AdminAsyncBody<List<int>>(
            load: () async => [],
            isEmpty: (l) => l.isEmpty,
            empty: const Text('nothing'),
            builder: (_, v) => Text('$v'),
          ),
        ),
      );
      expect(find.text('nothing'), findsOneWidget);
    });
  });

  testWidgets('ops center shows snapshot rows and tables', (tester) async {
    await _pump(tester, OpsCenterScreen(repository: _Repo()));
    expect(find.text('Queued'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text('w1'), findsOneWidget);
  });

  testWidgets('ops center has a read-only errors tab that loads the groups', (
    tester,
  ) async {
    final repo = _RecordingRepo();
    await _pump(tester, OpsCenterScreen(repository: repo));
    await tester.ensureVisible(find.text('admin.sys.ops.errors'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin.sys.ops.errors'));
    await tester.pumpAndSettle();
    expect(repo.opsCalls, contains('errors'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ops center surfaces a 403 instead of an empty tab', (
    tester,
  ) async {
    await _pump(tester, OpsCenterScreen(repository: _Repo(fail: _status(403))));
    expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
  });

  testWidgets('system health lays out five tabs on a phone', (tester) async {
    await _pump(tester, SystemHealthScreen(repository: _Repo()));
    expect(find.text('admin.sys.health.system'), findsWidgets);
    expect(find.text('Percent'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('analytics overview formats KPI numbers', (tester) async {
    await _pump(tester, AnalyticsScreen(repository: _Repo()));
    expect(find.text('Total users'), findsOneWidget);
    expect(find.text('1.5K'), findsOneWidget);
    await tester.tap(find.text('admin.sys.analytics.funnels'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Signed up'), findsOneWidget);
  });

  testWidgets('roles expand to their permissions, read only', (tester) async {
    await _pump(tester, RolesScreen(repository: _Repo()));
    expect(find.text('Admin'), findsOneWidget);
    await tester.tap(find.text('Admin'));
    await tester.pumpAndSettle();
    expect(find.text('read, update'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });

  testWidgets('admin list is read only', (tester) async {
    await _pump(tester, AdminManagementScreen(repository: _Repo()));
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('admin.shell.roleSuper'), findsOneWidget);
    expect(find.byType(IconButton), findsOneWidget); // the menu button only
    expect(find.byType(Switch), findsNothing);
  });

  group('audit log', () {
    testWidgets('lists events with facet chips and no overflow at 375', (
      tester,
    ) async {
      await _pump(
        tester,
        LogsScreen(repository: _Logs()),
        size: const Size(375, 700),
      );
      expect(find.text('login'), findsWidgets);
      expect(find.text('user'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty list shows the empty title', (tester) async {
      await _pump(tester, LogsScreen(repository: _Logs(empty: true)));
      expect(find.text('admin.sys.audit.empty'), findsOneWidget);
    });

    testWidgets('a 403 on facets is the whole screen answer', (tester) async {
      await _pump(
        tester,
        LogsScreen(repository: _Logs(facetError: _status(403))),
      );
      expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
    });
  });
}
