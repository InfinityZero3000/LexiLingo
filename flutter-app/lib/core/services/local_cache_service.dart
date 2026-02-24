import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'database_helper.dart';

/// Local SQLite cache for API responses (Layer 1 in 3-layer cache).
///
/// Provides offline-first data access with configurable TTL per content type.
/// Falls back to stale cached data when network is unavailable.
///
/// Phase 0 Infrastructure: Required by all content features.
class LocalCacheService {
  static final LocalCacheService instance = LocalCacheService._();
  LocalCacheService._();

  static const String _tableName = 'api_cache';

  /// TTL per content type — how long local cache is considered "fresh"
  static const Map<String, Duration> ttlConfig = {
    'news': Duration(hours: 2),
    'youtube': Duration(hours: 24),
    'podcast': Duration(hours: 6),
    'book': Duration(days: 7),
    'dictionary': Duration(days: 30),
    'game': Duration(hours: 12),
  };

  /// Get cached data or fetch from network.
  ///
  /// 1. Check local SQLite cache
  /// 2. If fresh → return cached data
  /// 3. If stale/missing → call [fetchFn]
  /// 4. On network error → return stale cache if available
  ///
  /// Returns null only if no cache exists AND fetch fails.
  Future<Map<String, dynamic>?> getOrFetch({
    required String key,
    required String type,
    required Future<Map<String, dynamic>> Function() fetchFn,
  }) async {
    final db = await DatabaseHelper.instance.database;

    // 1. Check local cache
    final cached = await db.query(
      _tableName,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (cached.isNotEmpty) {
      final entry = cached.first;
      final updatedAt = DateTime.parse(entry['updated_at'] as String);
      final age = DateTime.now().difference(updatedAt);
      final maxAge = ttlConfig[type] ?? const Duration(hours: 1);

      if (age < maxAge) {
        // Fresh cache
        return jsonDecode(entry['data'] as String) as Map<String, dynamic>;
      }
    }

    // 2. Fetch from backend
    try {
      final result = await fetchFn();
      await _upsert(key, type, jsonEncode(result));
      return result;
    } catch (e) {
      // 3. Serve stale cache on error (offline-first)
      if (cached.isNotEmpty) {
        return jsonDecode(cached.first['data'] as String)
            as Map<String, dynamic>;
      }
      rethrow;
    }
  }

  /// Get cached list data or fetch from network.
  Future<List<dynamic>?> getOrFetchList({
    required String key,
    required String type,
    required Future<List<dynamic>> Function() fetchFn,
  }) async {
    final db = await DatabaseHelper.instance.database;

    final cached = await db.query(
      _tableName,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (cached.isNotEmpty) {
      final entry = cached.first;
      final updatedAt = DateTime.parse(entry['updated_at'] as String);
      final age = DateTime.now().difference(updatedAt);
      final maxAge = ttlConfig[type] ?? const Duration(hours: 1);

      if (age < maxAge) {
        return jsonDecode(entry['data'] as String) as List<dynamic>;
      }
    }

    try {
      final result = await fetchFn();
      await _upsert(key, type, jsonEncode(result));
      return result;
    } catch (e) {
      if (cached.isNotEmpty) {
        return jsonDecode(cached.first['data'] as String) as List<dynamic>;
      }
      rethrow;
    }
  }

  /// Store data in cache manually (e.g., after a successful API call).
  Future<void> put(String key, String type, dynamic data) async {
    await _upsert(key, type, jsonEncode(data));
  }

  /// Get cached data without fetching (for checking if cache exists).
  Future<dynamic> get(String key) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      _tableName,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isNotEmpty) {
      return jsonDecode(result.first['data'] as String);
    }
    return null;
  }

  /// Check if a cache entry exists and is fresh.
  Future<bool> isFresh(String key, String type) async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.query(
      _tableName,
      where: 'cache_key = ?',
      whereArgs: [key],
      limit: 1,
    );

    if (result.isEmpty) return false;

    final updatedAt = DateTime.parse(result.first['updated_at'] as String);
    final age = DateTime.now().difference(updatedAt);
    final maxAge = ttlConfig[type] ?? const Duration(hours: 1);
    return age < maxAge;
  }

  /// Remove a specific cache entry.
  Future<void> invalidate(String key) async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(_tableName, where: 'cache_key = ?', whereArgs: [key]);
  }

  /// Remove all cache entries of a specific type.
  Future<int> invalidateType(String type) async {
    final db = await DatabaseHelper.instance.database;
    return await db.delete(
      _tableName,
      where: 'content_type = ?',
      whereArgs: [type],
    );
  }

  /// Remove expired cache entries to free storage.
  Future<int> clearExpired() async {
    final db = await DatabaseHelper.instance.database;
    int totalCleared = 0;

    for (final entry in ttlConfig.entries) {
      final cutoff =
          DateTime.now().subtract(entry.value * 2).toIso8601String();
      final count = await db.delete(
        _tableName,
        where: 'content_type = ? AND updated_at < ?',
        whereArgs: [entry.key, cutoff],
      );
      totalCleared += count;
    }

    return totalCleared;
  }

  /// Get total cache size (number of entries).
  Future<int> getCacheSize() async {
    final db = await DatabaseHelper.instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM $_tableName');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  /// Clear all cache data.
  Future<void> clearAll() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete(_tableName);
  }

  // ──── Private helpers ────

  Future<void> _upsert(String key, String type, String dataJson) async {
    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(
      _tableName,
      {
        'cache_key': key,
        'content_type': type,
        'data': dataJson,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Create the cache table (called from DatabaseHelper migration).
  static Future<void> createTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $_tableName (
  cache_key TEXT PRIMARY KEY,
  content_type TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cache_type ON $_tableName (content_type)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_cache_updated ON $_tableName (updated_at)',
    );
  }
}
