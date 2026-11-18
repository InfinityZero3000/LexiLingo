String _str(Object? v, [String fallback = '']) {
  final s = v?.toString();
  return s == null || s.isEmpty ? fallback : s;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String? _optStr(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

/// One row of `GET /admin/gem-grants`: gems an admin gave or corrected.
class GemGrant {
  const GemGrant({
    required this.id,
    required this.kind,
    required this.amount,
    required this.reason,
    this.createdAt,
    this.actorName,
    this.userId,
    this.userName,
    this.userEmail,
  });

  /// `gift` or `adjust`.
  final String id, kind, reason;
  final int amount;
  final String? createdAt, actorName, userId, userName, userEmail;

  factory GemGrant.fromJson(Map<String, dynamic> json) {
    final actor = json['actor'] is Map ? json['actor'] as Map : const {};
    final user = json['user'] is Map ? json['user'] as Map : const {};
    return GemGrant(
      id: _str(json['id']),
      kind: _str(json['kind'], 'gift'),
      amount: _int(json['amount']),
      reason: _str(json['reason']),
      createdAt: _optStr(json['created_at']),
      actorName: _optStr(actor['username']),
      userId: _optStr(user['id']),
      userName: _optStr(user['username']),
      userEmail: _optStr(user['email']),
    );
  }

  bool get isAdjustment => kind == 'adjust';

  String get recipient => userName ?? userEmail ?? '—';
}

/// What the signed-in admin may still give today (`usage` of
/// `GET /admin/gem-limits`).
class GemUsage {
  const GemUsage({
    required this.role,
    required this.maxPerAction,
    required this.dailyBudget,
    required this.spentToday,
    required this.remainingToday,
    required this.itemGiftMaxQty,
  });

  final String role;
  final int maxPerAction,
      dailyBudget,
      spentToday,
      remainingToday,
      itemGiftMaxQty;

  factory GemUsage.fromJson(Map<String, dynamic> json) => GemUsage(
    role: _str(json['role']),
    maxPerAction: _int(json['max_per_action']),
    dailyBudget: _int(json['daily_budget']),
    spentToday: _int(json['spent_today']),
    remainingToday: _int(json['remaining_today']),
    itemGiftMaxQty: _int(json['item_gift_max_qty']),
  );

  /// The most one gift may be right now: the per-action cap, or what is left of
  /// today's budget when that is smaller.
  int get giftCeiling =>
      remainingToday < maxPerAction ? remainingToday : maxPerAction;
}

/// Super-admin only: the configured caps (`config` of `GET /admin/gem-limits`).
class GemLimitsConfig {
  const GemLimitsConfig({
    required this.giftMaxAdmin,
    required this.giftMaxSuperAdmin,
    required this.budgetAdmin,
    required this.budgetSuperAdmin,
    required this.itemMaxQty,
  });

  final int giftMaxAdmin,
      giftMaxSuperAdmin,
      budgetAdmin,
      budgetSuperAdmin,
      itemMaxQty;

  factory GemLimitsConfig.fromJson(Map<String, dynamic> json) =>
      GemLimitsConfig(
        giftMaxAdmin: _int(json['gift_max_admin']),
        giftMaxSuperAdmin: _int(json['gift_max_super_admin']),
        budgetAdmin: _int(json['budget_admin']),
        budgetSuperAdmin: _int(json['budget_super_admin']),
        itemMaxQty: _int(json['item_max_qty']),
      );
}

class GemLimits {
  const GemLimits({required this.usage, this.config});

  final GemUsage usage;
  final GemLimitsConfig? config;

  factory GemLimits.fromJson(Map<String, dynamic> json) => GemLimits(
    usage: GemUsage.fromJson(
      json['usage'] is Map
          ? Map<String, dynamic>.from(json['usage'] as Map)
          : const {},
    ),
    config: json['config'] is Map
        ? GemLimitsConfig.fromJson(
            Map<String, dynamic>.from(json['config'] as Map),
          )
        : null,
  );
}
