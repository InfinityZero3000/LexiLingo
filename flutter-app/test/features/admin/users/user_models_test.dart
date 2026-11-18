import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/gem_ledger/data/gem_models.dart';
import 'package:lexilingo_app/features/admin/features/users/data/user_models.dart';

void main() {
  test('AdminUserItem reads a list row and falls back on missing fields', () {
    final user = AdminUserItem.fromJson({
      'id': 'u1',
      'email': 'ada@x.io',
      'display_name': '',
      'username': 'ada',
      'is_active': true,
      'role_level': 1,
      'role_slug': 'admin',
      'total_xp': 120,
      'streak_days': 3,
    });
    expect(user.id, 'u1');
    expect(user.displayName, 'ada');
    expect(user.shownName, 'ada');
    expect(user.roleLevel, 1);
    expect(user.level, 'A1');
    expect(user.rank, 'bronze');
    expect(user.copyWith(isActive: false).isActive, isFalse);
  });

  test('shownName uses the email local part when there is no name', () {
    final user = AdminUserItem.fromJson({'id': '1', 'email': 'bo@x.io'});
    expect(user.shownName, 'bo');
    expect(user.isActive, isFalse);
  });

  test('AdminUserDetail reads counts and providers', () {
    final d = AdminUserDetail.fromJson({
      'id': 'u1',
      'email': 'a@b.c',
      'username': 'a',
      'provider': ['google', 'local'],
      'is_active': true,
      'is_verified': true,
      'role_level': 0,
      'courses_enrolled': 4,
      'lessons_completed': '9',
    });
    expect(d.providers, ['google', 'local']);
    expect(d.coursesEnrolled, 4);
    expect(d.lessonsCompleted, 9);
    expect(d.shownName, 'a');
  });

  test('WalletPage and XpPage parse transactions', () {
    final wallet = WalletPage.fromJson({
      'balance': 50,
      'total_earned': 80,
      'total_spent': 30,
      'total': 2,
      'transactions': [
        {
          'id': 't1',
          'type': 'earn',
          'amount': 10,
          'balance_after': 50,
          'source': 'admin_gift',
          'created_at': '2026-11-01T10:00:00Z',
        },
        {'id': 't2', 'type': 'spend', 'amount': -5, 'balance_after': 40},
      ],
    });
    expect(wallet.balance, 50);
    expect(wallet.transactions, hasLength(2));
    expect(wallet.transactions.last.amount, -5);

    final xp = XpPage.fromJson({
      'total_xp': 700,
      'total': 1,
      'transactions': [
        {
          'id': 'x',
          'amount': 20,
          'base_amount': 10,
          'multiplier': 2,
          'source': 'lesson',
        },
      ],
    });
    expect(xp.totalXp, 700);
    expect(xp.transactions.single.multiplier, 2.0);
  });

  test('PremiumStatus and InventoryEntry parse', () {
    final p = PremiumStatus.fromJson({
      'exists': true,
      'is_active': true,
      'status': 'active',
      'source': 'admin',
      'expires_at': '2027-01-01T00:00:00Z',
      'force_enabled': false,
    });
    expect(p.isActive, isTrue);
    expect(p.source, 'admin');
    expect(PremiumStatus.fromJson(const {}).status, 'none');

    final i = InventoryEntry.fromJson({
      'id': 'i',
      'name': 'Streak freeze',
      'item_type': 'power_up',
      'quantity': 2,
      'is_active': true,
    });
    expect(i.quantity, 2);
    expect(i.isActive, isTrue);
  });

  test('GemGrant reads actor and recipient, GemLimits reads usage', () {
    final g = GemGrant.fromJson({
      'id': 'g',
      'kind': 'adjust',
      'amount': -20,
      'reason': 'refund',
      'actor': {'id': 'a', 'username': 'boss'},
      'user': {'id': 'u', 'username': null, 'email': 'e@x.io'},
    });
    expect(g.isAdjustment, isTrue);
    expect(g.actorName, 'boss');
    expect(g.recipient, 'e@x.io');

    final limits = GemLimits.fromJson({
      'usage': {
        'role': 'admin',
        'max_per_action': 500,
        'daily_budget': 2000,
        'spent_today': 1800,
        'remaining_today': 200,
        'item_gift_max_qty': 5,
      },
    });
    expect(limits.config, isNull);
    expect(limits.usage.giftCeiling, 200);
    expect(
      GemLimits.fromJson({
        'usage': {'max_per_action': 100, 'remaining_today': 900},
        'config': {'gift_max_admin': 100},
      }).config?.giftMaxAdmin,
      100,
    );
  });
}
