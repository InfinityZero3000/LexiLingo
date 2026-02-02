import 'package:equatable/equatable.dart';

/// Wallet Entity - User's gem balance
class WalletEntity extends Equatable {
  final String id;
  final String userId;
  final int gems;
  final int totalEarned;
  final int totalSpent;
  final DateTime? lastUpdated;

  const WalletEntity({
    required this.id,
    required this.userId,
    required this.gems,
    this.totalEarned = 0,
    this.totalSpent = 0,
    this.lastUpdated,
  });

  factory WalletEntity.fromJson(Map<String, dynamic> json) {
    return WalletEntity(
      id: json['id'] ?? '',
      userId: json['user_id'] ?? json['userId'] ?? '',
      gems: json['gems'] ?? 0,
      totalEarned: json['total_earned'] ?? json['totalEarned'] ?? 0,
      totalSpent: json['total_spent'] ?? json['totalSpent'] ?? 0,
      lastUpdated: json['last_updated'] != null
          ? DateTime.parse(json['last_updated'])
          : null,
    );
  }

  @override
  List<Object?> get props => [id, userId, gems];
}

/// Wallet Transaction Entity
class WalletTransactionEntity extends Equatable {
  final String id;
  final String type; // 'earn', 'spend', 'reward'
  final int amount;
  final String description;
  final String? referenceType; // 'achievement', 'purchase', 'challenge'
  final String? referenceId;
  final DateTime createdAt;

  const WalletTransactionEntity({
    required this.id,
    required this.type,
    required this.amount,
    required this.description,
    this.referenceType,
    this.referenceId,
    required this.createdAt,
  });

  bool get isEarning => type == 'earn' || type == 'reward';
  bool get isSpending => type == 'spend';

  factory WalletTransactionEntity.fromJson(Map<String, dynamic> json) {
    return WalletTransactionEntity(
      id: json['id'] ?? '',
      type: json['type'] ?? 'earn',
      amount: json['amount'] ?? 0,
      description: json['description'] ?? '',
      referenceType: json['reference_type'] ?? json['referenceType'],
      referenceId: json['reference_id'] ?? json['referenceId'],
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'])
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, type, amount, createdAt];
}
