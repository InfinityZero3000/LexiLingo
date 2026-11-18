import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/features/admin/features/users/data/users_repository.dart';
import 'package:lexilingo_app/features/admin/features/users/presentation/users_screen.dart';

import 'admin_screen_host.dart';
import 'admin_test_api.dart';

Map<String, dynamic> _user(
  String id,
  String name, {
  bool active = true,
  int role = 0,
}) => {
  'id': id,
  'email': '$name@x.io',
  'display_name': name,
  'is_active': active,
  'role_level': role,
  'total_xp': 100,
  'streak_days': 2,
};

Map<String, dynamic> _page(
  List<Map<String, dynamic>> users, {
  int? total,
  int pages = 1,
}) => {
  'data': {
    'users': users,
    'total': total ?? users.length,
    'page': 1,
    'page_size': 20,
    'total_pages': pages,
  },
};

void main() {
  testWidgets('shows a skeleton, then the learners with their status', (
    tester,
  ) async {
    final api = FakeAdminApi(
      (m, p, q) async => (
        200,
        _page([_user('1', 'Ada'), _user('2', 'Bo', active: false, role: 1)]),
      ),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pump();
    expect(find.byType(SkeletonList), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
    expect(find.text('Bo'), findsOneWidget);
    expect(find.text('admin.users.statusSuspended'), findsWidgets);
    expect(find.text('admin.users.roleAdmin'), findsWidgets);
    expect(find.text('admin.users.total'), findsOneWidget);
  });

  testWidgets('an empty result explains itself', (tester) async {
    final api = FakeAdminApi((m, p, q) async => (200, _page([])));
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('admin.users.emptyTitle'), findsOneWidget);
    expect(find.text('admin.users.emptyBody'), findsOneWidget);
  });

  testWidgets('a server error offers a retry that reloads', (tester) async {
    var fail = true;
    final api = FakeAdminApi(
      (m, p, q) async =>
          fail ? (500, {'detail': 'boom'}) : (200, _page([_user('1', 'Ada')])),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsNothing);
    expect(find.text('common.tryAgain'), findsOneWidget);

    fail = false;
    await tester.tap(find.text('common.tryAgain'));
    await tester.pumpAndSettle();
    expect(find.text('Ada'), findsOneWidget);
  });

  testWidgets('403 is shown as no access, not as an error', (tester) async {
    final api = FakeAdminApi(
      (m, p, q) async => (403, {'detail': 'Permission required: users:read'}),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
    expect(find.text('common.tryAgain'), findsNothing);
  });

  testWidgets('typing searches after a pause; filters reload from page one', (
    tester,
  ) async {
    final api = FakeAdminApi(
      (m, p, q) async => (200, _page([_user('1', 'Ada')])),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    expect(api.sent, hasLength(1));

    await tester.enterText(find.byType(TextField), 'ada');
    await tester.pump(const Duration(milliseconds: 100));
    expect(api.sent, hasLength(1), reason: 'still inside the debounce');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();
    expect(api.sent.last.query['search'], 'ada');
    expect(api.sent.last.query['page'], 1);

    await tester.ensureVisible(find.text('admin.users.roleAdmin').first);
    await tester.tap(find.text('admin.users.roleAdmin').first);
    await tester.pumpAndSettle();
    expect(api.sent.last.query['role'], 1);
    expect(api.sent.last.query['search'], 'ada');

    await tester.ensureVisible(find.text('admin.users.statusSuspended').first);
    await tester.tap(find.text('admin.users.statusSuspended').first);
    await tester.pumpAndSettle();
    expect(api.sent.last.query['is_active'], false);
  });

  testWidgets('sorting from the menu sends sort_by', (tester) async {
    final api = FakeAdminApi(
      (m, p, q) async => (200, _page([_user('1', 'Ada')])),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.sort_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin.users.sortTopXp'));
    await tester.pumpAndSettle();
    expect(api.sent.last.query['sort_by'], 'total_xp');
  });

  testWidgets('load more fetches the next page and appends', (tester) async {
    final api = FakeAdminApi((m, p, q) async {
      final page = q['page'] as int;
      return (
        200,
        _page(
          [for (var i = 0; i < 3; i++) _user('p$page-$i', 'User${page}_$i')],
          total: 6,
          pages: 2,
        ),
      );
    });
    final repo = UsersRepository(api: api.client);
    await pumpAdminScreen(tester, UsersScreen(repository: repo));
    await tester.pumpAndSettle();
    expect(find.text('User1_0'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('coreKit.loadMore'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    await tester.tap(find.text('coreKit.loadMore'));
    await tester.pumpAndSettle();
    expect(api.sent.last.query['page'], 2);
    await tester.scrollUntilVisible(
      find.text('User2_2'),
      300,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('User2_2'), findsOneWidget);
  });

  testWidgets('tapping a learner opens their detail', (tester) async {
    final api = FakeAdminApi(
      (m, p, q) async => (200, _page([_user('42', 'Ada')])),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(find.text('detail 42'), findsOneWidget);
  });

  testWidgets('rows keep a 44px touch target', (tester) async {
    final api = FakeAdminApi(
      (m, p, q) async => (200, _page([_user('1', 'Ada')])),
    );
    await pumpAdminScreen(
      tester,
      UsersScreen(repository: UsersRepository(api: api.client)),
    );
    await tester.pumpAndSettle();
    final row = find.ancestor(
      of: find.text('Ada'),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row.first).height, greaterThanOrEqualTo(44));
  });
}
