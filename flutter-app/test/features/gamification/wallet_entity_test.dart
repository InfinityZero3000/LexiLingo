import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';

void main() {
  test('wallet maps backend gem totals and updated timestamp', () {
    final wallet = WalletEntity.fromJson({
      'id': 'wallet-1',
      'user_id': 'user-1',
      'gems': 75,
      'total_gems_earned': 125,
      'total_gems_spent': 50,
      'updated_at': '2026-06-06T00:00:00Z',
    });

    expect(wallet.userId, 'user-1');
    expect(wallet.gems, 75);
    expect(wallet.totalEarned, 125);
    expect(wallet.totalSpent, 50);
    expect(wallet.lastUpdated, DateTime.parse('2026-06-06T00:00:00Z'));
  });

  test('wallet transaction maps backend transaction_type', () {
    final transaction = WalletTransactionEntity.fromJson({
      'id': 'tx-1',
      'transaction_type': 'spend',
      'amount': -20,
      'description': 'Purchased avatar',
      'created_at': '2026-06-06T00:00:00Z',
    });

    expect(transaction.type, 'spend');
    expect(transaction.isSpending, isTrue);
  });
}
