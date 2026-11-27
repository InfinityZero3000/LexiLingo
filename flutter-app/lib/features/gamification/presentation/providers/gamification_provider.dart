import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
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
  }) : _repository = repository,
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

  /// No balance and the last load failed: show a retry, not a fake 0.
  bool get walletUnavailable => _wallet == null && _walletError != null;
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

  /// Owned, usable in-game power-ups of a given [itemType] (e.g.
  /// [ShopItemEntity.effectTimeFreeze]), used by the games feature's
  /// power-up tray to show what the player can consume mid-game.
  List<InventoryItemEntity> powerUpsOf(String itemType) => _inventory
      .where((i) => i.item.effectType == itemType && i.quantity > 0)
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

  // ============== Session ==============
  /// Bumped by [reset]; a response that started before it belongs to the
  /// previous account and is dropped.
  int _epoch = 0;

  /// Drops every per-user value so the next account never sees the last one's.
  void reset() {
    _epoch++;
    _walletRequest++;
    _wallet = null;
    _transactions = [];
    _isLoadingWallet = false;
    _walletError = null;
    _pendingStarterReward = null;
    _isLoadingStarterReward = false;
    _shopItems = [];
    _isLoadingShop = false;
    _shopError = null;
    _selectedCategory = 'all';
    _inventory = [];
    _isLoadingInventory = false;
    _inventoryError = null;
    _leaderboards.clear();
    _loadingLeaderboardLeagues.clear();
    _leagueStatus = null;
    _isLoadingLeagueStatus = false;
    _leaderboardError = null;
    _selectedLeague = 'bronze';
    _leagueChangedFrom = null;
    _leagueChangedTo = null;
    notifyListeners();
  }

  // ============== Wallet Methods ==============
  int _walletRequest = 0;

  Future<void> loadWallet() async {
    final request = ++_walletRequest;
    _isLoadingWallet = true;
    _walletError = null;
    notifyListeners();
    try {
      final wallet = await _repository.getWallet();
      if (request == _walletRequest) _wallet = wallet;
    } catch (e) {
      if (request == _walletRequest) _walletError = e.toString();
      debugPrint('Error loading wallet: $e');
    } finally {
      if (request == _walletRequest) {
        _isLoadingWallet = false;
        notifyListeners();
      }
    }
  }

  Future<void> loadTransactions({int limit = 50}) async {
    final epoch = _epoch;
    try {
      final transactions = await _repository.getTransactions(limit: limit);
      if (epoch != _epoch) return;
      _transactions = transactions;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading transactions: $e');
    }
  }

  Future<StarterRewardEntity?> loadPendingStarterReward() async {
    if (!_enableStarterReward) return null;
    if (_isLoadingStarterReward) return _pendingStarterReward;
    final epoch = _epoch;
    _isLoadingStarterReward = true;
    notifyListeners();
    try {
      final reward = await _repository.getPendingStarterReward();
      if (epoch != _epoch) return null;
      _pendingStarterReward = reward;
      return reward;
    } catch (e) {
      debugPrint('Error loading starter reward: $e');
      return null;
    } finally {
      if (epoch == _epoch) {
        _isLoadingStarterReward = false;
        notifyListeners();
      }
    }
  }

  Future<bool> acknowledgeStarterReward() async {
    if (!_enableStarterReward) return false;
    try {
      final epoch = _epoch;
      final ok = await _repository.acknowledgeStarterReward();
      if (ok && epoch == _epoch) {
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
    final epoch = _epoch;
    _isLoadingShop = true;
    _shopError = null;
    notifyListeners();
    try {
      final items = await _repository.getShopItems();
      if (epoch == _epoch) _shopItems = items;
    } catch (e) {
      if (epoch == _epoch) _shopError = e.toString();
      debugPrint('Error loading shop items: $e');
    } finally {
      if (epoch == _epoch) {
        _isLoadingShop = false;
        notifyListeners();
      }
    }
  }

  void setCategory(String category) {
    _selectedCategory = category;
    notifyListeners();
  }

  bool _purchaseNeedsVerifiedEmail = false;

  /// The last purchase was refused because the account's email is unverified.
  bool get purchaseNeedsVerifiedEmail => _purchaseNeedsVerifiedEmail;

  Future<bool> purchaseItem(String itemId, {int quantity = 1}) async {
    _purchaseNeedsVerifiedEmail = false;
    try {
      final ok = await _repository.purchaseItem(itemId, quantity: quantity);
      if (ok) await Future.wait([loadWallet(), loadInventory()]);
      return ok;
    } catch (e) {
      _purchaseNeedsVerifiedEmail =
          e is ApiErrorException && e.details?['reason'] == 'email_unverified';
      debugPrint('Error purchasing item: $e');
      return false;
    }
  }

  ShopItemEntity? get heartRefillItem {
    for (final item in _shopItems) {
      if (item.effectType == ShopItemEntity.effectHeartRefill) return item;
    }
    return null;
  }

  /// Loads whatever the out-of-hearts sheet needs to price a refill.
  Future<void> prepareHeartRefill() async {
    await Future.wait([
      if (_shopItems.isEmpty) loadShopItems(),
      if (_wallet == null) loadWallet(),
      loadInventory(),
    ]);
  }

  /// Uses a Heart Refill on the learner's unfinished attempt, buying one
  /// first unless one is already owned (a failed earlier apply must not be
  /// charged twice).
  Future<bool> refillLessonHearts() async {
    final refill = heartRefillItem;
    if (refill == null) return false;
    InventoryItemEntity? owned = _ownedHeartRefill();
    if (owned == null) {
      if (gems < refill.priceGems) return false;
      if (!await purchaseItem(refill.id)) return false;
      owned = _ownedHeartRefill();
      if (owned == null) return false;
    }
    return useItem(owned.id);
  }

  InventoryItemEntity? _ownedHeartRefill() {
    for (final entry in _inventory) {
      if (entry.item.effectType == ShopItemEntity.effectHeartRefill &&
          entry.quantity > 0) {
        return entry;
      }
    }
    return null;
  }

  // ============== Inventory Methods ==============
  Future<void> loadInventory() async {
    final epoch = _epoch;
    _isLoadingInventory = true;
    _inventoryError = null;
    notifyListeners();
    try {
      final inventory = await _repository.getInventory();
      if (epoch == _epoch) _inventory = inventory;
    } catch (e) {
      if (epoch == _epoch) _inventoryError = e.toString();
      debugPrint('Error loading inventory: $e');
    } finally {
      if (epoch == _epoch) {
        _isLoadingInventory = false;
        notifyListeners();
      }
    }
  }

  Future<bool> useItem(String inventoryId) async {
    final effects = await useItemWithEffects(inventoryId);
    return effects != null;
  }

  /// Uses an inventory item and returns its applied effects payload
  /// (e.g. `{"seconds": 10}` for a Time Freeze), or null on failure.
  /// Used by the games feature's power-up tray to apply the right
  /// gameplay effect after a successful consume.
  Future<Map<String, dynamic>?> useItemWithEffects(
    String inventoryId, {
    String? gameSessionId,
  }) async {
    try {
      final effects = await _repository.useItem(
        inventoryId,
        gameSessionId: gameSessionId,
      );
      if (effects != null) await loadInventory();
      return effects;
    } catch (e) {
      debugPrint('Error using item: $e');
      return null;
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
    final epoch = _epoch;
    _selectedLeague = targetLeague;
    _loadingLeaderboardLeagues.add(targetKey);
    _leaderboardError = null;
    notifyListeners();
    try {
      final data = await _repository.getLeaderboard(targetLeague);
      if (epoch == _epoch) _leaderboards[targetKey] = data;
    } catch (e) {
      if (epoch == _epoch) _leaderboardError = e.toString();
      debugPrint('Error loading leaderboard: $e');
    } finally {
      if (epoch == _epoch) {
        _loadingLeaderboardLeagues.remove(targetKey);
        notifyListeners();
      }
    }
  }

  static const _leaguePrefKey = 'lexilingo.last_known_league';

  Future<void> loadLeagueStatus() async {
    final epoch = _epoch;
    _isLoadingLeagueStatus = true;
    notifyListeners();
    try {
      final status = await _repository.getLeagueStatus();
      if (epoch != _epoch) return;
      _leagueStatus = status;
      await _detectLeagueChange(status.league, epoch);
    } catch (e) {
      debugPrint('Error loading league status: $e');
    } finally {
      if (epoch == _epoch) {
        _isLoadingLeagueStatus = false;
        notifyListeners();
      }
    }
  }

  Future<void> _detectLeagueChange(String currentLeague, int epoch) async {
    final prefs = await SharedPreferences.getInstance();
    // Per learner: a shared key is what let one account's league show up as a
    // "league changed" banner on the next, and clearing it on sign-out raced a
    // quick sign-in. A learner's own value is theirs to keep.
    final key = await UserScopeService.scopedKey(_leaguePrefKey);
    if (epoch != _epoch) return;
    final previous = prefs.getString(key);
    if (previous != null && previous != currentLeague) {
      _leagueChangedFrom = previous;
      _leagueChangedTo = currentLeague;
    }
    await prefs.setString(key, currentLeague);
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
