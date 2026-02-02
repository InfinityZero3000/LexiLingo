import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';

/// Gamification Provider
/// Manages Shop, Wallet, Leaderboard, and Inventory state
class GamificationProvider extends ChangeNotifier {
  late final ApiClient _apiClient;

  GamificationProvider() {
    _apiClient = sl<ApiClient>();
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
    return _shopItems.where((item) => item.category == _selectedCategory).toList();
  }

  // ============== Inventory State ==============
  List<InventoryItemEntity> _inventory = [];
  bool _isLoadingInventory = false;
  String? _inventoryError;

  List<InventoryItemEntity> get inventory => _inventory;
  bool get isLoadingInventory => _isLoadingInventory;
  String? get inventoryError => _inventoryError;

  // ============== Leaderboard State ==============
  LeaderboardEntity? _leaderboard;
  LeagueStatusEntity? _leagueStatus;
  bool _isLoadingLeaderboard = false;
  String? _leaderboardError;
  String _selectedLeague = 'bronze';

  LeaderboardEntity? get leaderboard => _leaderboard;
  LeagueStatusEntity? get leagueStatus => _leagueStatus;
  bool get isLoadingLeaderboard => _isLoadingLeaderboard;
  String? get leaderboardError => _leaderboardError;
  String get selectedLeague => _selectedLeague;

  // ============== Wallet Methods ==============
  Future<void> loadWallet() async {
    _isLoadingWallet = true;
    _walletError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/wallet');
      if (response['success'] == true && response['data'] != null) {
        _wallet = WalletEntity.fromJson(response['data']);
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
      if (response['success'] == true && response['data'] != null) {
        _transactions = (response['data'] as List)
            .map((e) => WalletTransactionEntity.fromJson(e))
            .toList();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  // ============== Shop Methods ==============
  Future<void> loadShopItems() async {
    _isLoadingShop = true;
    _shopError = null;
    notifyListeners();

    try {
      final response = await _apiClient.get('/gamification/shop');
      if (response['success'] == true && response['data'] != null) {
        _shopItems = (response['data'] as List)
            .map((e) => ShopItemEntity.fromJson(e))
            .toList();
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
        body: {
          'item_id': itemId,
          'quantity': quantity,
        },
      );

      if (response['success'] == true) {
        // Reload wallet and inventory
        await Future.wait([
          loadWallet(),
          loadInventory(),
        ]);
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
      if (response['success'] == true && response['data'] != null) {
        final items = response['data']['items'] as List? ?? [];
        _inventory = items
            .map((e) => InventoryItemEntity.fromJson(e))
            .toList();
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
        '/gamification/inventory/$inventoryId/use',
      );

      if (response['success'] == true) {
        await loadInventory();
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('Error using item: $e');
      return false;
    }
  }

  // ============== Leaderboard Methods ==============
  Future<void> loadLeaderboard({String? league}) async {
    _isLoadingLeaderboard = true;
    _leaderboardError = null;
    notifyListeners();

    final targetLeague = league ?? _selectedLeague;

    try {
      final response = await _apiClient.get(
        '/gamification/leaderboard?league=$targetLeague',
      );
      
      if (response['success'] == true && response['data'] != null) {
        _leaderboard = LeaderboardEntity.fromJson(response['data']);
        _selectedLeague = targetLeague;
      }
    } catch (e) {
      _leaderboardError = e.toString();
      debugPrint('Error loading leaderboard: $e');
    } finally {
      _isLoadingLeaderboard = false;
      notifyListeners();
    }
  }

  Future<void> loadLeagueStatus() async {
    try {
      final response = await _apiClient.get('/gamification/leaderboard/me');
      if (response['success'] == true && response['data'] != null) {
        _leagueStatus = LeagueStatusEntity.fromJson(response['data']);
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error loading league status: $e');
    }
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
