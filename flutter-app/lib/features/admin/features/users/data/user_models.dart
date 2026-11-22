String _str(Object? v, [String fallback = '']) {
  final s = v?.toString();
  return s == null || s.isEmpty ? fallback : s;
}

int _int(Object? v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}') ?? 0;

String? _optStr(Object? v) {
  final s = v?.toString();
  return s == null || s.isEmpty ? null : s;
}

List<Map<String, dynamic>> _maps(Object? v) => v is List
    ? v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
    : const [];

/// One row of `GET /admin/users`.
class AdminUserItem {
  const AdminUserItem({
    required this.id,
    required this.email,
    required this.displayName,
    required this.roleSlug,
    required this.level,
    required this.rank,
    this.avatarUrl,
    this.createdAt,
    this.lastLogin,
    required this.isActive,
    required this.isVerified,
    required this.roleLevel,
    required this.totalXp,
    required this.numericLevel,
    required this.streakDays,
  });

  final String id, email, displayName, roleSlug, level, rank;
  final String? avatarUrl, createdAt, lastLogin;
  final bool isActive, isVerified;
  final int roleLevel, totalXp, numericLevel, streakDays;

  factory AdminUserItem.fromJson(Map<String, dynamic> json) => AdminUserItem(
    id: _str(json['id']),
    email: _str(json['email']),
    displayName: _str(_optStr(json['display_name']) ?? json['username']),
    avatarUrl: _optStr(json['avatar_url']),
    isActive: json['is_active'] == true,
    isVerified: json['is_verified'] == true,
    roleSlug: _str(json['role_slug'], 'user'),
    roleLevel: _int(json['role_level']),
    totalXp: _int(json['total_xp']),
    numericLevel: _int(json['numeric_level']),
    rank: _str(json['rank'], 'bronze'),
    level: _str(json['cefr_level'], 'A1'),
    streakDays: _int(json['streak_days']),
    createdAt: _optStr(json['created_at']),
    lastLogin: _optStr(json['last_login']),
  );

  /// Name to show: the display name, else the part of the email before `@`.
  String get shownName => displayName.isNotEmpty
      ? displayName
      : (email.contains('@') ? email.split('@').first : email);

  AdminUserItem copyWith({bool? isActive}) => AdminUserItem(
    id: id,
    email: email,
    displayName: displayName,
    roleSlug: roleSlug,
    level: level,
    rank: rank,
    avatarUrl: avatarUrl,
    createdAt: createdAt,
    lastLogin: lastLogin,
    isActive: isActive ?? this.isActive,
    isVerified: isVerified,
    roleLevel: roleLevel,
    totalXp: totalXp,
    numericLevel: numericLevel,
    streakDays: streakDays,
  );
}

/// `GET /admin/users/{id}`.
class AdminUserDetail {
  const AdminUserDetail({
    required this.id,
    required this.email,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.isActive,
    required this.isVerified,
    required this.roleSlug,
    required this.roleLevel,
    required this.providers,
    this.createdAt,
    this.lastLogin,
    required this.totalXp,
    required this.coursesEnrolled,
    required this.coursesCompleted,
    required this.lessonsCompleted,
    required this.dailyActivities,
  });

  final String id, email, username, displayName, roleSlug;
  final String? avatarUrl, createdAt, lastLogin;
  final bool isActive, isVerified;
  final int roleLevel,
      totalXp,
      coursesEnrolled,
      coursesCompleted,
      lessonsCompleted,
      dailyActivities;
  final List<String> providers;

  factory AdminUserDetail.fromJson(Map<String, dynamic> json) {
    final providers = json['provider'];
    return AdminUserDetail(
      id: _str(json['id']),
      email: _str(json['email']),
      username: _str(json['username']),
      displayName: _str(_optStr(json['display_name']) ?? json['username']),
      avatarUrl: _optStr(json['avatar_url']),
      isActive: json['is_active'] == true,
      isVerified: json['is_verified'] == true,
      roleSlug: _str(json['role_slug'], 'user'),
      roleLevel: _int(json['role_level']),
      providers: providers is List
          ? providers.map((e) => e.toString()).toList()
          : const [],
      createdAt: _optStr(json['created_at']),
      lastLogin: _optStr(json['last_login']),
      totalXp: _int(json['total_xp']),
      coursesEnrolled: _int(json['courses_enrolled']),
      coursesCompleted: _int(json['courses_completed']),
      lessonsCompleted: _int(json['lessons_completed']),
      dailyActivities: _int(json['daily_activities']),
    );
  }

  String get shownName => displayName.isNotEmpty
      ? displayName
      : (username.isNotEmpty ? username : email);
}

/// One entry of `GET /admin/users/{id}/activity`.
class UserActivityEntry {
  const UserActivityEntry({
    required this.date,
    required this.type,
    required this.description,
    required this.xpEarned,
  });

  final String date, type, description;
  final int xpEarned;

  factory UserActivityEntry.fromJson(Map<String, dynamic> json) =>
      UserActivityEntry(
        date: _str(json['activity_date']),
        type: _str(json['activity_type']),
        description: _str(json['description']),
        xpEarned: _int(json['xp_earned']),
      );
}

class WalletTransaction {
  const WalletTransaction({
    required this.id,
    required this.type,
    required this.amount,
    required this.balanceAfter,
    this.source,
    this.description,
    this.createdAt,
  });

  final String id, type;
  final int amount, balanceAfter;
  final String? source, description, createdAt;

  factory WalletTransaction.fromJson(Map<String, dynamic> json) =>
      WalletTransaction(
        id: _str(json['id']),
        type: _str(json['type']),
        amount: _int(json['amount']),
        balanceAfter: _int(json['balance_after']),
        source: _optStr(json['source']),
        description: _optStr(json['description']),
        createdAt: _optStr(json['created_at']),
      );
}

/// `GET /admin/users/{id}/wallet`: balances plus one page of the gem ledger.
class WalletPage {
  const WalletPage({
    required this.balance,
    required this.totalEarned,
    required this.totalSpent,
    required this.total,
    required this.transactions,
  });

  final int balance, totalEarned, totalSpent, total;
  final List<WalletTransaction> transactions;

  factory WalletPage.fromJson(Map<String, dynamic> json) => WalletPage(
    balance: _int(json['balance']),
    totalEarned: _int(json['total_earned']),
    totalSpent: _int(json['total_spent']),
    total: _int(json['total']),
    transactions: _maps(
      json['transactions'],
    ).map(WalletTransaction.fromJson).toList(),
  );
}

class XpTransaction {
  const XpTransaction({
    required this.id,
    required this.amount,
    required this.baseAmount,
    required this.multiplier,
    required this.source,
    this.sourceDetail,
    this.createdAt,
  });

  final String id, source;
  final int amount, baseAmount;
  final double multiplier;
  final String? sourceDetail, createdAt;

  factory XpTransaction.fromJson(Map<String, dynamic> json) => XpTransaction(
    id: _str(json['id']),
    amount: _int(json['amount']),
    baseAmount: _int(json['base_amount']),
    multiplier: json['multiplier'] is num
        ? (json['multiplier'] as num).toDouble()
        : 1,
    source: _str(json['source']),
    sourceDetail: _optStr(json['source_detail']),
    createdAt: _optStr(json['created_at']),
  );
}

/// `GET /admin/users/{id}/xp-transactions`.
class XpPage {
  const XpPage({
    required this.totalXp,
    required this.total,
    required this.transactions,
  });

  final int totalXp, total;
  final List<XpTransaction> transactions;

  factory XpPage.fromJson(Map<String, dynamic> json) => XpPage(
    totalXp: _int(json['total_xp']),
    total: _int(json['total']),
    transactions: _maps(
      json['transactions'],
    ).map(XpTransaction.fromJson).toList(),
  );
}

class InventoryEntry {
  const InventoryEntry({
    required this.id,
    required this.name,
    required this.itemType,
    required this.quantity,
    required this.isActive,
    this.expiresAt,
    this.purchasedAt,
  });

  final String id, name, itemType;
  final int quantity;
  final bool isActive;
  final String? expiresAt, purchasedAt;

  factory InventoryEntry.fromJson(Map<String, dynamic> json) => InventoryEntry(
    id: _str(json['id']),
    name: _str(json['name']),
    itemType: _str(json['item_type']),
    quantity: _int(json['quantity']),
    isActive: json['is_active'] == true,
    expiresAt: _optStr(json['expires_at']),
    purchasedAt: _optStr(json['purchased_at']),
  );
}

/// `GET /admin/users/{id}/entitlements` (premium only).
class PremiumStatus {
  const PremiumStatus({
    required this.exists,
    required this.isActive,
    required this.status,
    this.source,
    this.productId,
    this.expiresAt,
    this.syncedAt,
    required this.forceEnabled,
  });

  final bool exists, isActive, forceEnabled;
  final String status;
  final String? source, productId, expiresAt, syncedAt;

  factory PremiumStatus.fromJson(Map<String, dynamic> json) => PremiumStatus(
    exists: json['exists'] == true,
    isActive: json['is_active'] == true,
    status: _str(json['status'], 'none'),
    source: _optStr(json['source']),
    productId: _optStr(json['product_id']),
    expiresAt: _optStr(json['expires_at']),
    syncedAt: _optStr(json['synced_at']),
    forceEnabled: json['force_enabled'] == true,
  );
}
