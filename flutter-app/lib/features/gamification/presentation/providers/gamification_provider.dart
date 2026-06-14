import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';

/// Gamification Provider
/// Manages Shop, Wallet, Leaderboard, and Inventory state
class GamificationProvider extends ChangeNotifier {
  final ApiClient _apiClient;
  final bool _enableStarterReward;

  GamificationProvider({ApiClient? apiClient, bool? enableStarterReward})
    : _apiClient = apiClient ?? sl<ApiClient>(),
      _enableStarterReward =
          enableStarterReward ?? ApiConfig.enableStarterReward;

  bool _isSuccessResponse(Map<String, dynamic> response) {
    final success = response['success'];
    return success is bool ? success : true;
  }

  dynamic _extractData(Map<String, dynamic> response) {
    return response.containsKey('data') ? response['data'] : response;
  }

  // ============== Wallet State ==============
  WalletEntity? _wallet;
  List<WalletTransactionEntity> _transactions = [];
  bool _isLoadingWallet = false;
  String? _walletError;

  WalletEntity? get wallet => _wallet;
  List<WalletTransactionEntity> get transactions => _transactions;
  bool get isLoadingWallet => _isLoadingWallet;
  String? get walletError => _walletError;
  int get gems => _wallet?.gems ?? 0;
  StarterRewardEntity? _pendingStarterReward;
  bool _isLoadingStarterReward = false;

  StarterRewardEntity? get pendingStarterReward => _pendingStarterReward;
  bool get isLoadingStarterReward => _isLoadingStarterReward;

  // ============== Shop State ==============
  List<ShopItemEntity> _shopItems = [];
  bool _isLoadingShop = false;
  String? _shopError;
  String _selectedCategory = 'all';

  List<ShopItemEntity> get shopItems => _shopItems;
  bool get isLoadingShop => _isLoadingShop;
  String? get shopError => _shopError;
  String get selectedCategory => _selectedCategory;

  List<ShopItemEntity> get filteredShopItems {
    if (_selectedCategory == 'all') return _shopItems;
    return _shopItems
        .where((item) => item.category == _selectedCategory)
        .toList();
  }

  // ============== Inventory State ==============
  List<InventoryItemEntity> _inventory = [];
  bool _isLoadingInventory = false;
  String? _inventoryError;

  List<InventoryItemEntity> get inventory => _inventory;

  /// Active boosts: items that are currently active and have not expired.
  List<InventoryItemEntity> get activeBoosts => _inventory
      .where((i) => i.isActive && !i.isExpired && i.expiresAt != null)
      .toList();

  bool get isLoadingInventory => _isLoadingInventory;
  String? get inventoryError => _inventoryError;
  bool ownsItem(String shopItemId) =>
      _inventory.any((entry) => entry.item.id == shopItemId);
  List<String> get ownedAvatarUrls => _inventory
      .where((entry) => entry.item.isAvatar)
      .map((entry) => entry.item.avatarUrl)
      .whereType<String>()
      .toSet()
      .toList();

  // ============== Leaderboard State ==============
  final Map<String, LeaderboardEntity> _leaderboards = {};
  final Set<String> _loadingLeaderboardLeagues = {};
  LeagueStatusEntity? _leagueStatus;
  bool _isLoadingLeagueStatus = false;
  String? _leaderboardError;
  String _selectedLeague = 'bronze';

  // League change detection (populated by loadLeagueStatus)
  String? _leagueChangedFrom;
  String? _leagueChangedTo;

  LeaderboardEntity? get leaderboard =>
      _leaderboards[_selectedLeague.toLowerCase()];
  LeaderboardEntity? leaderboardFor(String league) =>
      _leaderboards[league.toLowerCase()];
  LeagueStatusEntity? get leagueStatus => _leagueStatus;
  bool get isLoadingLeagueStatus => _isLoadingLeagueStatus;
  bool get isLoadingLeaderboard => _loadingLeaderboardLeagues.isNotEmpty;
  bool isLoadingLeaderboardFor(String league) =>
      _loadingLeaderboardLeagues.contains(league.toLowerCase());
  String? get leaderboardError => _leaderboardError;
  String get selectedLeague => _selectedLeague;

  /// Non-null when the user was promoted or demoted since the last session.
  String? get leagueChangedFrom => _leagueChangedFrom;
  String? get leagueChangedTo => _leagueChangedTo;

  /// Call after showing LeagueCeremonyScreen to clear the pending state.
  void clearLeagueChange() {
    _leagueChangedFrom = null;
    _leagueChangedTo = null;
    notifyListeners();
  }

  // ============== Wallet Methods ==============
  Future<void> loadWallet() async {
    _isLoadingWallet = true;
    _walletError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/wallet');
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        _wallet = WalletEntity.fromJson(data);
      }
    } catch (e) {
      _walletError = e.toString();
      debugPrint('Error loading wallet: $e');
    } finally {
      _isLoadingWallet = false;
      notifyListeners();
    }
  }

  Future<void> loadTransactions({int limit = 50}) async {
    try {
      final response = await _apiClient.get(
        '/gamification/wallet/history?limit=$limit',
      );
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is List) {
        _transactions = data
            .map((e) => WalletTransactionEntity.fromJson(e))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  Future<StarterRewardEntity?> loadPendingStarterReward() async {
    if (!_enableStarterReward) return null;
    if (_isLoadingStarterReward) return _pendingStarterReward;
    _isLoadingStarterReward = true;
    notifyListeners();

    try {
      final response = await _apiClient.get(
        '/gamification/rewards/starter/pending',
      );
      final data = _extractData(response);
      _pendingStarterReward =
          _isSuccessResponse(response) && data is Map<String, dynamic>
          ? StarterRewardEntity.fromJson(data)
          : null;
      return _pendingStarterReward;
    } catch (e) {
      debugPrint('Error loading starter reward: $e');
      return null;
    } finally {
      _isLoadingStarterReward = false;
      notifyListeners();
    }
  }

  Future<bool> acknowledgeStarterReward() async {
    if (!_enableStarterReward) return false;
    try {
      final response = await _apiClient.post(
        '/gamification/rewards/starter/seen',
      );
      if (!_isSuccessResponse(response)) return false;
      _pendingStarterReward = null;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('Error acknowledging starter reward: $e');
      return false;
    }
  }

  // ============== Shop Methods ==============
  Future<void> loadShopItems() async {
    _isLoadingShop = true;
    _shopError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/shop');
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is List) {
        _shopItems = data.map((e) => ShopItemEntity.fromJson(e)).toList();
      }
    } catch (e) {
      _shopError = e.toString();
      debugPrint('Error loading shop items: $e');
    } finally {
      _isLoadingShop = false;
      notifyListeners();
    }
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async {
    try {
      final response = await _apiClient.post(
        '/gamification/shop/purchase',
        body: {'item_id': itemId, 'quantity': quantity},
      );

      if (_isSuccessResponse(response)) {
        // Reload wallet and inventory
        await Future.wait([loadWallet(), loadInventory()]);
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error purchasing item: $e');
      return false;
    }
  }

  // ============== Inventory Methods ==============
  Future<void> loadInventory() async {
    _isLoadingInventory = true;
    _inventoryError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/inventory');
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final items = data['items'] as List? ?? [];
        _inventory = items.map((e) => InventoryItemEntity.fromJson(e)).toList();
      }
    } catch (e) {
      _inventoryError = e.toString();
      debugPrint('Error loading inventory: $e');
    } finally {
      _isLoadingInventory = false;
      notifyListeners();
    }
  }

  Future<bool> useItem(String inventoryId) async {
    try {
      final response = await _apiClient.post(
        '/gamification/inventory/use',
        body: {'inventory_id': inventoryId},
      );

      if (_isSuccessResponse(response)) {
        await loadInventory();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error using item: $e');
      return false;
    }
  }

  Future<String?> equipAvatar(String shopItemId) async {
    InventoryItemEntity? inventoryItem;
    for (final entry in _inventory) {
      if (entry.item.id == shopItemId && entry.item.isAvatar) {
        inventoryItem = entry;
        break;
      }
    }
    if (inventoryItem == null) return null;

    try {
      final response = await _apiClient.post(
        '/gamification/inventory/avatar/equip',
        body: {'inventory_id': inventoryItem.id},
      );
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        return data['avatar_url'] as String?;
      }
    } catch (e) {
      debugPrint('Error equipping avatar: $e');
    }
    return null;
  }

  // ============== Leaderboard Methods ==============
  Future<void> loadLeaderboard({String? league}) async {
    final targetLeague = league ?? _selectedLeague;
    final targetKey = targetLeague.toLowerCase();

    _loadingLeaderboardLeagues.add(targetKey);
    _leaderboardError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get(
        '/gamification/leaderboard?league=$targetLeague',
      );

      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        final newLeaderboard = LeaderboardEntity.fromJson(data);
        _leaderboards[targetKey] = newLeaderboard;
        _selectedLeague = targetLeague;
      } else {
        _leaderboardError = 'Leaderboard payload is invalid';
      }
    } catch (e) {
      _leaderboardError = e.toString();
      debugPrint('Error loading leaderboard: $e');
    } finally {
      _loadingLeaderboardLeagues.remove(targetKey);
      notifyListeners();
    }
  }

  static const _leaguePrefKey = 'lexilingo.last_known_league';

  Future<void> loadLeagueStatus() async {
    _isLoadingLeagueStatus = true;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/leaderboard/me');
      final data = _extractData(response);
      if (_isSuccessResponse(response) && data is Map<String, dynamic>) {
        _leagueStatus = LeagueStatusEntity.fromJson(data);
        await _detectLeagueChange(_leagueStatus!.league);
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    } finally {
      _isLoadingLeagueStatus = false;
      notifyListeners();
    }
  }

  Future<void> _detectLeagueChange(String currentLeague) async {
    final prefs = await SharedPreferences.getInstance();
    final previous = prefs.getString(_leaguePrefKey);
    if (previous != null && previous != currentLeague) {
      _leagueChangedFrom = previous;
      _leagueChangedTo = currentLeague;
    }
    await prefs.setString(_leaguePrefKey, currentLeague);
  }

  void setLeague(String league) {
    if (_selectedLeague != league) {
      _selectedLeague = league;
      loadLeaderboard(league: league);
    }
  }

  // ============== Combined Methods ==============
  Future<void> loadAllGamificationData() async {
    await Future.wait([
      loadWallet(),
      loadShopItems(),
      loadInventory(),
      loadLeaderboard(),
      loadLeagueStatus(),
    ]);
  }
}
