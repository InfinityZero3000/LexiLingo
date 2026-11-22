import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/gem_ledger/data/gem_ledger_repository.dart';
import 'package:lexilingo_app/features/admin/features/users/data/users_repository.dart';
import 'package:lexilingo_app/features/admin/features/users/presentation/user_detail_screen.dart';

import 'admin_screen_host.dart';
import 'admin_test_api.dart';

Map<String, dynamic> _detail({bool active = true}) => {
  'id': 'u1',
  'email': 'ada@x.io',
  'username': 'ada',
  'display_name': 'Ada Lovelace',
  'is_active': active,
  'is_verified': true,
  'role_slug': 'user',
  'role_level': 0,
  'provider': ['google'],
  'created_at': '2026-01-05T10:00:00Z',
  'last_login': '2026-11-10T08:30:00Z',
  'total_xp': 1234,
  'courses_enrolled': 3,
  'courses_completed': 1,
  'lessons_completed': 20,
};

FakeAdminApi _api({
  bool active = true,
  int detailStatus = 200,
  int Function(String method, String path)? status,
  Map<String, dynamic>? limits,
}) {
  return FakeAdminApi((method, path, query) async {
    final forced = status?.call(method, path);
    if (forced != null && forced != 200) return (forced, {'detail': 'nope'});
    if (path == '/admin/users/u1' && method == 'GET') {
      return detailStatus == 200
          ? (200, {'data': _detail(active: active)})
          : (detailStatus, {'detail': 'x'});
    }
    if (path.endsWith('/activity')) {
      return (
        200,
        {
          'data': [
            {
              'activity_date': '2026-11-09',
              'activity_type': 'lesson_completed',
              'description': 'Completed lesson (Score: 90%)',
              'xp_earned': 15,
            },
          ],
        },
      );
    }
    if (path.endsWith('/wallet')) {
      return (
        200,
        {
          'data': {
            'balance': 75,
            'total_earned': 100,
            'total_spent': 25,
            'total': 1,
            'transactions': [
              {
                'id': 't',
                'type': 'earn',
                'amount': 50,
                'balance_after': 75,
                'description': 'Admin gift',
                'created_at': '2026-11-01T10:00:00Z',
              },
            ],
          },
        },
      );
    }
    if (path.endsWith('/xp-transactions')) {
      return (
        200,
        {
          'data': {
            'total_xp': 1234,
            'total': 1,
            'transactions': [
              {
                'id': 'x',
                'amount': 30,
                'base_amount': 15,
                'multiplier': 2,
                'source': 'lesson',
                'created_at': '2026-11-01T10:00:00Z',
              },
            ],
          },
        },
      );
    }
    if (path.endsWith('/inventory')) {
      return (
        200,
        {
          'data': {
            'items': [
              {
                'id': 'i',
                'name': 'Streak freeze',
                'item_type': 'power_up',
                'quantity': 2,
                'is_active': false,
              },
            ],
          },
        },
      );
    }
    if (path.endsWith('/entitlements')) {
      return (
        200,
        {
          'data': {
            'exists': true,
            'is_active': true,
            'status': 'active',
            'source': 'admin',
            'expires_at': '2027-01-01T00:00:00Z',
            'force_enabled': false,
          },
        },
      );
    }
    if (path == '/admin/gem-limits') {
      return (
        200,
        {
          'data': {
            'usage':
                limits ??
                {
                  'role': 'admin',
                  'max_per_action': 100,
                  'daily_budget': 500,
                  'spent_today': 50,
                  'remaining_today': 450,
                  'item_gift_max_qty': 3,
                },
          },
        },
      );
    }
    return (200, {'success': true});
  });
}

Future<void> _open(
  WidgetTester tester,
  FakeAdminApi api, {
  List<String> slugs = const ['users:read'],
}) async {
  await pumpAdminScreen(
    tester,
    UserDetailScreen(
      userId: 'u1',
      repository: UsersRepository(api: api.client),
      gemRepository: GemLedgerRepository(api: api.client),
    ),
    slugs: slugs,
    size: const Size(420, 1200),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('overview shows the profile, counts and recent activity', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api);
    expect(find.text('Ada Lovelace'), findsOneWidget);
    expect(find.text('ada@x.io'), findsOneWidget);
    expect(find.text('1234'), findsOneWidget);
    expect(find.text('20'), findsOneWidget);
    expect(find.text('05/01/2026'), findsOneWidget);
    expect(find.text('Completed lesson (Score: 90%)'), findsOneWidget);
    expect(find.text('+15'), findsOneWidget);
    expect(find.text('admin.webOnly.open'), findsOneWidget);
  });

  testWidgets('a plain reader sees no suspend or gift buttons', (tester) async {
    await _open(tester, _api());
    expect(find.text('admin.users.detail.suspend'), findsNothing);
    expect(find.text('admin.users.gift.title'), findsNothing);
  });

  testWidgets('403 on the learner is shown as no access', (tester) async {
    await _open(tester, _api(detailStatus: 403));
    expect(find.text('admin.access.forbiddenTitle'), findsOneWidget);
  });

  testWidgets('suspending asks first, then PUTs the status and reloads', (
    tester,
  ) async {
    final api = _api();
    await _open(tester, api, slugs: ['users:read', 'users:update']);
    await tester.tap(find.text('admin.users.detail.suspend'));
    await tester.pumpAndSettle();
    expect(find.text('admin.users.detail.suspendTitle'), findsOneWidget);
    expect(api.where('PUT', '/admin/users/u1/status'), isEmpty);

    await tester.tap(find.text('admin.users.detail.suspend').last);
    await tester.pumpAndSettle();
    expect(api.where('PUT', '/admin/users/u1/status').single.body, {
      'is_active': false,
    });
    expect(api.where('GET', '/admin/users/u1'), hasLength(2));
  });

  testWidgets('cancelling the confirmation changes nothing', (tester) async {
    final api = _api();
    await _open(tester, api, slugs: ['users:read', 'users:update']);
    await tester.tap(find.text('admin.users.detail.suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('common.cancel'));
    await tester.pumpAndSettle();
    expect(api.where('PUT', '/admin/users/u1/status'), isEmpty);
  });

  testWidgets('a suspended account offers reactivation', (tester) async {
    final api = _api(active: false);
    await _open(tester, api, slugs: ['users:read', 'users:update']);
    expect(find.text('admin.users.detail.suspend'), findsNothing);
    await tester.tap(find.text('admin.users.detail.activate'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin.users.detail.activate').last);
    await tester.pumpAndSettle();
    expect(api.where('PUT', '/admin/users/u1/status').single.body, {
      'is_active': true,
    });
  });

  testWidgets('a failed suspend reports the server reason and keeps going', (
    tester,
  ) async {
    final api = _api(
      status: (m, p) => m == 'PUT' && p.endsWith('/status') ? 400 : 200,
    );
    await _open(tester, api, slugs: ['users:read', 'users:update']);
    await tester.tap(find.text('admin.users.detail.suspend'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('admin.users.detail.suspend').last);
    await tester.pumpAndSettle();
    expect(find.text('nope'), findsOneWidget);
    expect(find.text('admin.users.detail.suspend'), findsOneWidget);
  });

  group('gift gems', () {
    Future<void> openSheet(WidgetTester tester, FakeAdminApi api) async {
      await _open(tester, api, slugs: ['users:read', 'gifts:grant']);
      await tester.tap(find.text('admin.users.gift.title'));
      await tester.pumpAndSettle();
    }

    testWidgets('validates amount and reason before asking', (tester) async {
      final api = _api();
      await openSheet(tester, api);
      await tester.tap(find.text('admin.users.gift.send'));
      await tester.pumpAndSettle();
      expect(find.text('admin.users.gift.amountInvalid'), findsOneWidget);
      expect(find.text('admin.users.gift.reasonShort'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).first, '101');
      await tester.enterText(find.byType(TextFormField).last, 'prize');
      await tester.tap(find.text('admin.users.gift.send'));
      await tester.pumpAndSettle();
      expect(
        find.text('admin.users.gift.amountInvalid'),
        findsOneWidget,
        reason: 'over the per-gift cap of 100',
      );
      expect(api.where('POST', '/admin/users/u1/gift'), isEmpty);
    });

    testWidgets('sends the gift after a confirmation', (tester) async {
      final api = _api();
      await openSheet(tester, api);
      await tester.enterText(find.byType(TextFormField).first, '50');
      await tester.enterText(find.byType(TextFormField).last, 'contest prize');
      await tester.tap(find.text('admin.users.gift.send'));
      await tester.pumpAndSettle();
      expect(find.text('admin.users.gift.confirmTitle'), findsOneWidget);
      expect(api.where('POST', '/admin/users/u1/gift'), isEmpty);

      await tester.tap(find.text('admin.users.gift.send').last);
      await tester.pumpAndSettle();
      expect(api.where('POST', '/admin/users/u1/gift').single.body, {
        'gift_type': 'gems',
        'amount': 50,
        'reason': 'contest prize',
      });
      expect(find.text('admin.users.gift.sent'), findsOneWidget);
    });

    testWidgets('an exhausted daily budget blocks the gift', (tester) async {
      final api = _api(
        limits: {
          'role': 'admin',
          'max_per_action': 100,
          'daily_budget': 100,
          'spent_today': 100,
          'remaining_today': 0,
          'item_gift_max_qty': 3,
        },
      );
      await openSheet(tester, api);
      await tester.enterText(find.byType(TextFormField).first, '5');
      await tester.enterText(find.byType(TextFormField).last, 'contest prize');
      await tester.tap(find.text('admin.users.gift.send'));
      await tester.pumpAndSettle();
      expect(find.text('admin.users.gift.budgetUsed'), findsOneWidget);
      expect(api.where('POST', '/admin/users/u1/gift'), isEmpty);
    });

    testWidgets('a server refusal stays in the sheet with its reason', (
      tester,
    ) async {
      final api = _api(
        status: (m, p) => m == 'POST' && p.endsWith('/gift') ? 400 : 200,
      );
      await openSheet(tester, api);
      await tester.enterText(find.byType(TextFormField).first, '10');
      await tester.enterText(find.byType(TextFormField).last, 'contest prize');
      await tester.tap(find.text('admin.users.gift.send'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('admin.users.gift.send').last);
      await tester.pumpAndSettle();
      expect(find.text('nope'), findsOneWidget);
      expect(find.text('admin.users.gift.title'), findsWidgets);
    });
  });

  testWidgets('wallet tab shows the balance and the ledger', (tester) async {
    final api = _api();
    await _open(tester, api);
    await tester.tap(find.text('admin.users.detail.tabWallet'));
    await tester.pumpAndSettle();
    expect(find.text('75'), findsOneWidget);
    expect(find.text('Admin gift'), findsOneWidget);
    expect(find.text('+50'), findsOneWidget);
    expect(
      api.where('GET', '/admin/users/u1/wallet').single.query['limit'],
      20,
    );
  });

  testWidgets('xp tab shows total and awards with the multiplier', (
    tester,
  ) async {
    await _open(tester, _api());
    await tester.tap(find.text('admin.users.detail.tabXp'));
    await tester.pumpAndSettle();
    expect(find.text('lesson'), findsOneWidget);
    expect(find.text('+30'), findsOneWidget);
    expect(find.text('admin.users.xp.multiplier'), findsOneWidget);
  });

  testWidgets('items tab shows premium and inventory', (tester) async {
    await _open(tester, _api());
    await tester.tap(find.text('admin.users.detail.tabItems'));
    await tester.pumpAndSettle();
    expect(find.text('admin.users.items.premiumActive'), findsOneWidget);
    expect(find.text('Streak freeze'), findsOneWidget);
    expect(find.text('×2'), findsOneWidget);
  });

  testWidgets('a failing tab offers a retry', (tester) async {
    final api = _api(status: (m, p) => p.endsWith('/inventory') ? 500 : 200);
    await _open(tester, api);
    await tester.tap(find.text('admin.users.detail.tabItems'));
    await tester.pumpAndSettle();
    expect(find.text('common.tryAgain'), findsOneWidget);
  });
}
