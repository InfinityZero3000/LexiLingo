import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/features/admin/features/gem_ledger/data/gem_ledger_repository.dart';
import 'package:lexilingo_app/features/admin/features/users/data/users_repository.dart';

import 'admin_test_api.dart';

void main() {
  test('listUsers sends page, filters and sort, and reads the page', () async {
    final api = FakeAdminApi(
      (method, path, query) async => (
        200,
        {
          'success': true,
          'data': {
            'users': [
              {'id': '1', 'email': 'a@x.io', 'display_name': 'A'},
              {'id': '2', 'email': 'b@x.io', 'display_name': 'B'},
            ],
            'total': 45,
            'page': 2,
            'page_size': 20,
            'total_pages': 3,
          },
        },
      ),
    );
    final repo = UsersRepository(api: api.client);

    final page = await repo.listUsers(const PageRequest(index: 1, size: 20), {
      'search': ' ada ',
      'role': 1,
      'is_active': false,
      'sort': UserSort.topXp,
    });

    final q = api.sent.single.query;
    expect(api.sent.single.path, '/admin/users');
    expect(q['page'], 2);
    expect(q['page_size'], 20);
    expect(q['search'], 'ada');
    expect(q['role'], 1);
    expect(q['is_active'], false);
    expect(q['sort_by'], 'total_xp');
    expect(q['order'], 'desc');
    expect(page.items.map((u) => u.id), ['1', '2']);
    expect(page.total, 45);
    expect(page.hasMore, isTrue);
  });

  test('listUsers omits empty filters and stops on the last page', () async {
    final api = FakeAdminApi(
      (m, p, q) async => (
        200,
        {
          'data': {'users': [], 'total': 0, 'total_pages': 1},
        },
      ),
    );
    final page = await UsersRepository(
      api: api.client,
    ).listUsers(const PageRequest(index: 0, size: 20), const {});
    final q = api.sent.single.query;
    expect(q.containsKey('search'), isFalse);
    expect(q.containsKey('role'), isFalse);
    expect(q.containsKey('is_active'), isFalse);
    expect(q['sort_by'], 'created_at');
    expect(page.hasMore, isFalse);
  });

  test(
    'detail, activity, wallet, xp, inventory and premium hit their paths',
    () async {
      final api = FakeAdminApi((method, path, query) async {
        if (path.endsWith('/activity')) {
          return (
            200,
            {
              'data': [
                {
                  'activity_date': '2026-11-01',
                  'activity_type': 'lesson_completed',
                  'description': 'Completed lesson',
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
              'data': {'balance': 7, 'total': 0, 'transactions': []},
            },
          );
        }
        if (path.endsWith('/xp-transactions')) {
          return (
            200,
            {
              'data': {'total_xp': 9, 'total': 0, 'transactions': []},
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
                    'name': 'Hat',
                    'item_type': 'avatar',
                    'quantity': 1,
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
              'data': {'exists': false, 'status': 'none'},
            },
          );
        }
        return (
          200,
          {
            'data': {'id': 'u9', 'email': 'z@x.io', 'username': 'z'},
          },
        );
      });
      final repo = UsersRepository(api: api.client);

      expect((await repo.getUser('u9')).id, 'u9');
      expect((await repo.getActivity('u9')).single.xpEarned, 15);
      expect(
        api.where('GET', '/admin/users/u9/activity').single.query['days'],
        30,
      );

      final wallet = await repo.getWallet(
        'u9',
        const PageRequest(index: 2, size: 20),
      );
      expect(wallet.balance, 7);
      final walletQuery = api
          .where('GET', '/admin/users/u9/wallet')
          .single
          .query;
      expect(walletQuery['limit'], 20);
      expect(walletQuery['offset'], 40);

      expect(
        (await repo.getXp('u9', const PageRequest(index: 0, size: 20))).totalXp,
        9,
      );
      expect((await repo.getInventory('u9')).single.name, 'Hat');
      expect((await repo.getPremium('u9')).exists, isFalse);
    },
  );

  test('setActive PUTs the status and giftGems POSTs a gems gift', () async {
    final api = FakeAdminApi((m, p, q) async => (200, {'success': true}));
    final repo = UsersRepository(api: api.client);

    await repo.setActive('u1', false);
    final put = api.where('PUT', '/admin/users/u1/status').single;
    expect(put.body, {'is_active': false});

    await repo.giftGems('u1', amount: 50, reason: 'contest prize');
    final post = api.where('POST', '/admin/users/u1/gift').single;
    expect(post.body, {
      'gift_type': 'gems',
      'amount': 50,
      'reason': 'contest prize',
    });
  });

  test('gem ledger reads grants with filters and the limits', () async {
    final api = FakeAdminApi((method, path, query) async {
      if (path == '/admin/gem-limits') {
        return (
          200,
          {
            'data': {
              'usage': {
                'role': 'admin',
                'max_per_action': 100,
                'daily_budget': 500,
                'spent_today': 100,
                'remaining_today': 400,
                'item_gift_max_qty': 3,
              },
            },
          },
        );
      }
      return (
        200,
        {
          'data': {
            'total': 31,
            'items': [
              {
                'id': 'g1',
                'kind': 'gift',
                'amount': 10,
                'reason': 'welcome',
                'actor': {'username': 'boss'},
                'user': {'username': 'ada', 'email': 'ada@x.io'},
              },
            ],
          },
        },
      );
    });
    final repo = GemLedgerRepository(api: api.client);

    final page = await repo.listGrants(const PageRequest(index: 1, size: 20), {
      'kind': 'gift',
      'date_from': '2026-11-01',
    });
    final q = api.where('GET', '/admin/gem-grants').single.query;
    expect(q['limit'], 20);
    expect(q['offset'], 20);
    expect(q['kind'], 'gift');
    expect(q['date_from'], '2026-11-01');
    expect(q.containsKey('date_to'), isFalse);
    expect(page.total, 31);
    expect(page.items.single.recipient, 'ada');

    final limits = await repo.getLimits();
    expect(limits.usage.remainingToday, 400);
    expect(limits.config, isNull);
  });
}
