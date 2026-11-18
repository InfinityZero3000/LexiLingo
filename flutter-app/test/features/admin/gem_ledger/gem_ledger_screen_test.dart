import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/gem_ledger/data/gem_ledger_repository.dart';
import 'package:lexilingo_app/features/admin/features/gem_ledger/presentation/gem_ledger_screen.dart';

import '../users/admin_screen_host.dart';
import '../users/admin_test_api.dart';

Map<String, dynamic> _limits({bool config = false}) => {
  'data': {
    'usage': {
      'role': 'admin',
      'max_per_action': 100,
      'daily_budget': 500,
      'spent_today': 120,
      'remaining_today': 380,
      'item_gift_max_qty': 3,
    },
    if (config) 'config': {'gift_max_admin': 100},
  },
};

Map<String, dynamic> _grants(List<Map<String, dynamic>> items) => {
  'data': {'total': items.length, 'items': items},
};

Map<String, dynamic> _grant(String id, int amount, {String kind = 'gift'}) => {
  'id': id,
  'kind': kind,
  'amount': amount,
  'reason': 'reason $id',
  'created_at': '2026-11-02T09:15:00Z',
  'actor': {'username': 'boss'},
  'user': {'username': 'learner$id', 'email': '$id@x.io'},
};

Future<void> _open(WidgetTester tester, FakeAdminApi api) => pumpAdminScreen(
  tester,
  GemLedgerScreen(repository: GemLedgerRepository(api: api.client)),
  slugs: ['gifts:read'],
).then((_) => tester.pumpAndSettle());

void main() {
  testWidgets('shows today\'s allowance and the grants', (tester) async {
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') return (200, _limits());
      return (
        200,
        _grants([_grant('a', 50), _grant('b', -20, kind: 'adjust')]),
      );
    });
    await _open(tester, api);
    expect(find.text('380'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('learnera'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);
    expect(find.text('-20'), findsOneWidget);
    expect(find.text('reason a'), findsOneWidget);
    expect(find.text('02/11/2026 09:15'.substring(0, 10)), findsNothing);
    expect(find.text('admin.webOnly.open'), findsNothing);
  });

  testWidgets('a super admin is pointed to the web admin for the caps', (
    tester,
  ) async {
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') return (200, _limits(config: true));
      return (200, _grants([]));
    });
    await _open(tester, api);
    expect(find.text('admin.webOnly.open'), findsOneWidget);
  });

  testWidgets('filtering by kind reloads from the first page', (tester) async {
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') return (200, _limits());
      return (200, _grants([_grant('a', 50)]));
    });
    await _open(tester, api);
    expect(api.where('GET', '/admin/gem-grants').single.query['offset'], 0);
    await tester.ensureVisible(find.text('admin.gems.kindAdjust').first);
    await tester.tap(find.text('admin.gems.kindAdjust').first);
    await tester.pumpAndSettle();
    final last = api.where('GET', '/admin/gem-grants').last.query;
    expect(last['kind'], 'adjust');
    expect(last['offset'], 0);
  });

  testWidgets('no grants explains itself', (tester) async {
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') return (200, _limits());
      return (200, _grants([]));
    });
    await _open(tester, api);
    expect(find.text('admin.gems.emptyTitle'), findsOneWidget);
  });

  testWidgets(
    '403 on the ledger is no access; a limits failure only dims the card',
    (tester) async {
      final api = FakeAdminApi((m, p, q) async {
        if (p == '/admin/gem-limits') return (500, {'detail': 'boom'});
        return (403, {'detail': 'Permission required: gifts:read'});
      });
      await _open(tester, api);
      expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
      expect(find.text('admin.gems.limitsFailed'), findsOneWidget);
    },
  );

  testWidgets('a limits failure can be retried', (tester) async {
    var fail = true;
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') {
        return fail ? (500, {'detail': 'boom'}) : (200, _limits());
      }
      return (200, _grants([_grant('a', 5)]));
    });
    await _open(tester, api);
    fail = false;
    await tester.tap(find.text('common.retry'));
    await tester.pumpAndSettle();
    expect(find.text('380'), findsOneWidget);
  });

  testWidgets('rows keep a 44px touch target and show no overflow', (
    tester,
  ) async {
    final api = FakeAdminApi((m, p, q) async {
      if (p == '/admin/gem-limits') return (200, _limits());
      return (200, _grants([_grant('a', 5)]));
    });
    await _open(tester, api);
    expect(
      tester.getSize(find.byType(GrantTile).first).height,
      greaterThanOrEqualTo(44),
    );
    expect(tester.takeException(), isNull);
  });
}
