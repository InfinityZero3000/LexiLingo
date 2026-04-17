import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

/// Encrypted local cache scoped by user ID.
///
/// This cache stores JSON payloads encrypted at rest in SQLite.
/// Each user scope has a dedicated symmetric key managed in secure storage.
class EncryptedLocalCacheService {
  EncryptedLocalCacheService._();
  static final EncryptedLocalCacheService instance =
      EncryptedLocalCacheService._();

  static const String tableName = 'secure_api_cache';
  static const int _maxEntriesPerUser = 500;
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );

  static const Map<String, Duration> ttlConfig = {
    'profile': Duration(hours: 1),
    'progress': Duration(minutes: 30),
    'leaderboard': Duration(hours: 6),
    'vocab': Duration(hours: 12),
    'chat': Duration(hours: 24),
  };

  final Map<String, _MemorySecureEntry> _memory = {};
  final Map<String, String> _memoryKeyFallback = {};

  Future<Map<String, dynamic>?> getOrFetchMap({
    required String userScope,
    required String namespace,
    required String key,
    required Future<Map<String, dynamic>> Function() fetchFn,
  }) async {
    final cached = await getMap(
      userScope: userScope,
      namespace: namespace,
      key: key,
      enforceTtl: true,
    );
    if (cached != null) return cached;

    try {
      final remote = await fetchFn();
      await putJson(
        userScope: userScope,
        namespace: namespace,
        key: key,
        value: remote,
      );
      return remote;
    } catch (_) {
      return getMap(
        userScope: userScope,
        namespace: namespace,
        key: key,
        enforceTtl: false,
      );
    }
  }

  Future<List<dynamic>?> getOrFetchList({
    required String userScope,
    required String namespace,
    required String key,
    required Future<List<dynamic>> Function() fetchFn,
  }) async {
    final cached = await getList(
      userScope: userScope,
      namespace: namespace,
      key: key,
      enforceTtl: true,
    );
    if (cached != null) return cached;

    try {
      final remote = await fetchFn();
      await putJson(
        userScope: userScope,
        namespace: namespace,
        key: key,
        value: remote,
      );
      return remote;
    } catch (_) {
      return getList(
        userScope: userScope,
        namespace: namespace,
        key: key,
        enforceTtl: false,
      );
    }
  }

  Future<void> putJson({
    required String userScope,
    required String namespace,
    required String key,
    required dynamic value,
  }) async {
    final now = DateTime.now().toIso8601String();
    final dataJson = jsonEncode(value);

    if (kIsWeb) {
      _memory[_mkMemoryKey(userScope, namespace, key)] = _MemorySecureEntry(
        namespace: namespace,
        cipherText: dataJson,
        updatedAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
      );
      return;
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final cipher = await _encrypt(userScope: userScope, plainText: dataJson);
      await db.insert(tableName, {
        'cache_key': key,
        'user_scope': userScope,
        'namespace': namespace,
        'data': cipher,
        'updated_at': now,
        'last_accessed_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      await _enforceQuota(db, userScope);
    } catch (_) {
      _memory[_mkMemoryKey(userScope, namespace, key)] = _MemorySecureEntry(
        namespace: namespace,
        cipherText: dataJson,
        updatedAt: DateTime.now(),
        lastAccessedAt: DateTime.now(),
      );
    }
  }

  Future<Map<String, dynamic>?> getMap({
    required String userScope,
    required String namespace,
    required String key,
    required bool enforceTtl,
  }) async {
    final decoded = await _getDecoded(
      userScope: userScope,
      namespace: namespace,
      key: key,
      enforceTtl: enforceTtl,
    );
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<List<dynamic>?> getList({
    required String userScope,
    required String namespace,
    required String key,
    required bool enforceTtl,
  }) async {
    final decoded = await _getDecoded(
      userScope: userScope,
      namespace: namespace,
      key: key,
      enforceTtl: enforceTtl,
    );
    if (decoded is List<dynamic>) {
      return decoded;
    }
    return null;
  }

  Future<void> invalidate({
    required String userScope,
    required String namespace,
    required String key,
  }) async {
    if (kIsWeb) {
      _memory.remove(_mkMemoryKey(userScope, namespace, key));
      return;
    }

    _memory.remove(_mkMemoryKey(userScope, namespace, key));
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        tableName,
        where: 'cache_key = ? AND user_scope = ? AND namespace = ?',
        whereArgs: [key, userScope, namespace],
      );
    } catch (_) {
      // Memory fallback already handled.
    }
  }

  Future<void> invalidateNamespace({
    required String userScope,
    required String namespace,
  }) async {
    if (kIsWeb) {
      _memory.removeWhere(
        (k, v) =>
            k.startsWith('$userScope::$namespace::') && v.namespace == namespace,
      );
      return;
    }

    _memory.removeWhere(
      (k, v) =>
          k.startsWith('$userScope::$namespace::') && v.namespace == namespace,
    );
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(
        tableName,
        where: 'user_scope = ? AND namespace = ?',
        whereArgs: [userScope, namespace],
      );
    } catch (_) {
      // Memory fallback already handled.
    }
  }

  Future<void> clearUserScope(String userScope) async {
    if (kIsWeb) {
      _memory.removeWhere((k, _) => k.startsWith('$userScope::'));
      return;
    }

    _memory.removeWhere((k, _) => k.startsWith('$userScope::'));
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(tableName, where: 'user_scope = ?', whereArgs: [userScope]);
    } catch (_) {
      // Memory fallback already handled.
    }
  }

  Future<void> clearAll() async {
    if (kIsWeb) {
      _memory.clear();
      return;
    }

    _memory.clear();
    try {
      final db = await DatabaseHelper.instance.database;
      await db.delete(tableName);
    } catch (_) {
      // Memory fallback already handled.
    }
  }

  /// Rotates user encryption key and clears scoped cache to avoid stale ciphertext.
  Future<void> rotateKey(String userScope) async {
    await _deleteKey(userScope);
    await _getOrCreateKey(userScope);
    await clearUserScope(userScope);
  }

  Future<dynamic> _getDecoded({
    required String userScope,
    required String namespace,
    required String key,
    required bool enforceTtl,
  }) async {
    final ttl = ttlConfig[namespace] ?? const Duration(hours: 1);

    if (kIsWeb) {
      final entry = _memory[_mkMemoryKey(userScope, namespace, key)];
      if (entry == null) return null;
      if (enforceTtl && DateTime.now().difference(entry.updatedAt) > ttl) {
        return null;
      }
      entry.lastAccessedAt = DateTime.now();
      return jsonDecode(entry.cipherText);
    }

    try {
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        tableName,
        where: 'cache_key = ? AND user_scope = ? AND namespace = ?',
        whereArgs: [key, userScope, namespace],
        limit: 1,
      );

      if (rows.isEmpty) {
        final memEntry = _memory[_mkMemoryKey(userScope, namespace, key)];
        if (memEntry == null) return null;
        if (enforceTtl && DateTime.now().difference(memEntry.updatedAt) > ttl) {
          return null;
        }
        memEntry.lastAccessedAt = DateTime.now();
        return jsonDecode(memEntry.cipherText);
      }
      final row = rows.first;
      final updatedAt = DateTime.parse(row['updated_at'] as String);
      if (enforceTtl && DateTime.now().difference(updatedAt) > ttl) {
        return null;
      }

      final plain = await _decrypt(
        userScope: userScope,
        cipherText: row['data'] as String,
      );

      await db.update(
        tableName,
        {'last_accessed_at': DateTime.now().toIso8601String()},
        where: 'cache_key = ? AND user_scope = ? AND namespace = ?',
        whereArgs: [key, userScope, namespace],
      );

      return jsonDecode(plain);
    } catch (_) {
      final memEntry = _memory[_mkMemoryKey(userScope, namespace, key)];
      if (memEntry == null) return null;
      if (enforceTtl && DateTime.now().difference(memEntry.updatedAt) > ttl) {
        return null;
      }
      memEntry.lastAccessedAt = DateTime.now();
      return jsonDecode(memEntry.cipherText);
    }
  }

  Future<void> _enforceQuota(Database db, String userScope) async {
    final rows = await db.query(
      tableName,
      columns: ['cache_key', 'namespace'],
      where: 'user_scope = ?',
      whereArgs: [userScope],
      orderBy: 'last_accessed_at ASC',
    );

    final overflow = rows.length - _maxEntriesPerUser;
    if (overflow <= 0) return;

    for (var i = 0; i < overflow; i++) {
      final row = rows[i];
      await db.delete(
        tableName,
        where: 'cache_key = ? AND user_scope = ? AND namespace = ?',
        whereArgs: [row['cache_key'], userScope, row['namespace']],
      );
    }
  }

  Future<String> _encrypt({
    required String userScope,
    required String plainText,
  }) async {
    final keyBytes = await _getOrCreateKey(userScope);
    final ivBytes = _randomBytes(16);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
    );
    final encrypted = encrypter.encrypt(
      plainText,
      iv: encrypt.IV(Uint8List.fromList(ivBytes)),
    );
    final ivB64 = base64Encode(ivBytes);
    return '$ivB64:${encrypted.base64}';
  }

  Future<String> _decrypt({
    required String userScope,
    required String cipherText,
  }) async {
    final parts = cipherText.split(':');
    if (parts.length != 2) {
      return cipherText;
    }
    final keyBytes = await _getOrCreateKey(userScope);
    final ivBytes = base64Decode(parts[0]);
    final encrypter = encrypt.Encrypter(
      encrypt.AES(encrypt.Key(Uint8List.fromList(keyBytes))),
    );
    return encrypter.decrypt64(parts[1], iv: encrypt.IV(Uint8List.fromList(ivBytes)));
  }

  Future<List<int>> _getOrCreateKey(String userScope) async {
    final storageKey = _storageKey(userScope);
    final existing = await _readSecure(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return base64Decode(existing);
    }

    final keyBytes = _randomBytes(32);
    await _writeSecure(storageKey, base64Encode(keyBytes));
    return keyBytes;
  }

  Future<void> _deleteKey(String userScope) async {
    final key = _storageKey(userScope);
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return;
    }
    try {
      await _secureStorage.delete(key: key);
    } catch (_) {
      _memoryKeyFallback.remove(key);
    }
  }

  Future<String?> _readSecure(String key) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(key);
    }
    try {
      return await _secureStorage.read(key: key);
    } catch (_) {
      return _memoryKeyFallback[key];
    }
  }

  Future<void> _writeSecure(String key, String value) async {
    if (kIsWeb) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
    } catch (_) {
      _memoryKeyFallback[key] = value;
    }
  }

  List<int> _randomBytes(int length) {
    final random = Random.secure();
    return List<int>.generate(length, (_) => random.nextInt(256));
  }

  String _storageKey(String userScope) => 'secure_cache_key::$userScope';

  String _mkMemoryKey(String userScope, String namespace, String key) {
    return '$userScope::$namespace::$key';
  }

  static Future<void> createTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  cache_key TEXT NOT NULL,
  user_scope TEXT NOT NULL,
  namespace TEXT NOT NULL,
  data TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  last_accessed_at TEXT NOT NULL,
  PRIMARY KEY (cache_key, user_scope, namespace)
)
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_secure_cache_scope ON $tableName (user_scope)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_secure_cache_access ON $tableName (last_accessed_at)',
    );
  }
}

class _MemorySecureEntry {
  _MemorySecureEntry({
    required this.namespace,
    required this.cipherText,
    required this.updatedAt,
    required this.lastAccessedAt,
  });

  final String namespace;
  final String cipherText;
  final DateTime updatedAt;
  DateTime lastAccessedAt;
}
