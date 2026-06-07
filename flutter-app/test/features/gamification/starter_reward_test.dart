import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';

void main() {
  test('parses starter reward payload', () {
    final reward = StarterRewardEntity.fromJson({
      'reward_key': 'new_user_starter_gems_v1',
      'gems_awarded': 100,
      'current_balance': 100,
      'title': 'Welcome gift',
      'body': '100 Gems have been added.',
    });

    expect(reward.rewardKey, 'new_user_starter_gems_v1');
    expect(reward.gemsAwarded, 100);
    expect(reward.currentBalance, 100);
  });
}
