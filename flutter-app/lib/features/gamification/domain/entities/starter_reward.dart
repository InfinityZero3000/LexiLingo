import 'package:equatable/equatable.dart';

class StarterRewardEntity extends Equatable {
  final String rewardKey;
  final int gemsAwarded;
  final int currentBalance;
  final String title;
  final String body;

  const StarterRewardEntity({
    required this.rewardKey,
    required this.gemsAwarded,
    required this.currentBalance,
    required this.title,
    required this.body,
  });

  factory StarterRewardEntity.fromJson(Map<String, dynamic> json) {
    return StarterRewardEntity(
      rewardKey: json['reward_key'] as String? ?? '',
      gemsAwarded: (json['gems_awarded'] as num?)?.toInt() ?? 0,
      currentBalance: (json['current_balance'] as num?)?.toInt() ?? 0,
      title: json['title'] as String? ?? '',
      body: json['body'] as String? ?? '',
    );
  }

  @override
  List<Object?> get props => [
    rewardKey,
    gemsAwarded,
    currentBalance,
    title,
    body,
  ];
}
