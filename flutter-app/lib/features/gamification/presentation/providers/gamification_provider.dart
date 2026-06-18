import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/features/gamification/domain/repositories/gamification_repository.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/shop_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/inventory_item.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/starter_reward.dart';

/// Manages Shop, Wallet, Leaderboard, and Inventory state.
class GamificationProvider extends ChangeNotifier {
  GamificationProvider({
    required GamificationRepository repository,
    bool? enableStarterReward,
  })  : _repository = repository,
        _enableStarterReward =
            enableStarterReward ?? ApiConfig.enableStarterReward;

  final GamificationRepository _repository;
  final bool _enableStarterReward;

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

  String? get leagueChangedFrom => _leagueChangedFrom;
  String? get leagueChangedTo => _leagueChangedTo;

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
      _wallet = await _repository.getWallet();
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
      _transactions = await _repository.getTransactions(limit: limit);
      notifyListeners();
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
      _pendingStarterReward = await _repository.getPendingStarterReward();
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
      final ok = await _repository.acknowledgeStarterReward();
      if (ok) {
        _pendingStarterReward = null;
        notifyListeners();
      }
      return ok;
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
      _shopItems = await _repository.getShopItems();
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
      final ok = await _repository.purchaseItem(itemId, quantity: quantity);
      if (ok) await Future.wait([loadWallet(), loadInventory()]);
      return ok;
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
      _inventory = await _repository.getInventory();
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
      final ok = await _repository.useItem(inventoryId);
      if (ok) await loadInventory();
      return ok;
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
      return await _repository.equipAvatar(inventoryItem.id);
    } catch (e) {
      debugPrint('Error equipping avatar: $e');
      return null;
    }
  }

  // ============== Leaderboard Methods ==============
  Future<void> loadLeaderboard({String? league}) async {
    final targetLeague = league ?? _selectedLeague;
    final targetKey = targetLeague.toLowerCase();
    _loadingLeaderboardLeagues.add(targetKey);
    _leaderboardError = null;
    notifyListeners();
    try {
      final data = await _repository.getLeaderboard(targetLeague);
      _leaderboards[targetKey] = data;
      _selectedLeague = targetLeague;
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
      _leagueStatus = await _repository.getLeagueStatus();
      await _detectLeagueChange(_leagueStatus!.league);
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
