import 'package:lexilingo_app/core/network/api_client.dart';

abstract class GamificationRemoteDataSource {
  Future<Map<String, dynamic>> getWallet();
  Future<List<dynamic>> getTransactions({int limit = 50});
  Future<Map<String, dynamic>?> getPendingStarterReward();
  Future<bool> acknowledgeStarterReward();
  Future<List<dynamic>> getShopItems();
  Future<bool> purchaseItem(String itemId, {int quantity = 1});
  Future<Map<String, dynamic>> getInventory();

  /// Uses an inventory item; returns its `effects_applied` payload on
  /// success (e.g. `{"seconds": 10}` for a Time Freeze), or null on failure.
  Future<Map<String, dynamic>?> useItem(String inventoryId);
  Future<Map<String, dynamic>?> equipAvatar(String inventoryId);
  Future<Map<String, dynamic>> getLeaderboard(String league);
  Future<Map<String, dynamic>> getLeagueStatus();
}

class GamificationRemoteDataSourceImpl implements GamificationRemoteDataSource {
  GamificationRemoteDataSourceImpl(this._apiClient);

  final ApiClient _apiClient;

  static bool _ok(Map<String, dynamic> r) {
    final s = r['success'];
    return s is bool ? s : true;
  }

  static dynamic _data(Map<String, dynamic> r) =>
      r.containsKey('data') ? r['data'] : r;

  @override
  Future<Map<String, dynamic>> getWallet() async {
    final r = await _apiClient.get('/gamification/wallet');
    if (!_ok(r)) throw Exception('getWallet failed');
    return _data(r) as Map<String, dynamic>;
  }

  @override
  Future<List<dynamic>> getTransactions({int limit = 50}) async {
    final r = await _apiClient.get('/gamification/wallet/history?limit=$limit');
    if (!_ok(r)) return [];
    return _data(r) as List<dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> getPendingStarterReward() async {
    final r = await _apiClient.get('/gamification/rewards/starter/pending');
    if (!_ok(r)) return null;
    final d = _data(r);
    return d is Map<String, dynamic> ? d : null;
  }

  @override
  Future<bool> acknowledgeStarterReward() async {
    final r = await _apiClient.post('/gamification/rewards/starter/seen');
    return _ok(r);
  }

  @override
  Future<List<dynamic>> getShopItems() async {
    final r = await _apiClient.get('/gamification/shop');
    if (!_ok(r)) throw Exception('getShopItems failed');
    return _data(r) as List<dynamic>;
  }

  @override
  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async {
    final r = await _apiClient.post(
      '/gamification/shop/purchase',
      body: {'item_id': itemId, 'quantity': quantity},
    );
    return _ok(r);
  }

  @override
  Future<Map<String, dynamic>> getInventory() async {
    final r = await _apiClient.get('/gamification/inventory');
    if (!_ok(r)) throw Exception('getInventory failed');
    return _data(r) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>?> useItem(String inventoryId) async {
    final r = await _apiClient.post(
      '/gamification/inventory/use',
      body: {'inventory_id': inventoryId},
    );
    if (!_ok(r)) return null;
    final d = _data(r);
    if (d is! Map<String, dynamic>) return {};
    final effects = d['effects_applied'];
    return effects is Map<String, dynamic> ? effects : {};
  }

  @override
  Future<Map<String, dynamic>?> equipAvatar(String inventoryId) async {
    final r = await _apiClient.post(
      '/gamification/inventory/avatar/equip',
      body: {'inventory_id': inventoryId},
    );
    if (!_ok(r)) return null;
    final d = _data(r);
    return d is Map<String, dynamic> ? d : null;
  }

  @override
  Future<Map<String, dynamic>> getLeaderboard(String league) async {
    final r = await _apiClient.get('/gamification/leaderboard?league=$league');
    if (!_ok(r)) throw Exception('getLeaderboard failed');
    return _data(r) as Map<String, dynamic>;
  }

  @override
  Future<Map<String, dynamic>> getLeagueStatus() async {
    final r = await _apiClient.get('/gamification/leaderboard/me');
    if (!_ok(r)) throw Exception('getLeagueStatus failed');
    return _data(r) as Map<String, dynamic>;
  }
}
