import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:sqflite/sqflite.dart';

import 'database_helper.dart';

class SyncQueueItem {
  SyncQueueItem({
    required this.id,
    required this.userScope,
    required this.queueType,
    required this.payload,
    required this.idempotencyKey,
    required this.retryCount,
    required this.nextRetryAt,
  });

  final int id;
  final String userScope;
  final String queueType;
  final Map<String, dynamic> payload;
  final String idempotencyKey;
  final int retryCount;
  final DateTime nextRetryAt;
}

/// Persistent background sync queue with exponential backoff.
class BackgroundSyncQueueService {
  BackgroundSyncQueueService._();
  static final BackgroundSyncQueueService instance =
      BackgroundSyncQueueService._();

  static const String tableName = 'sync_queue';
  final StreamController<SyncQueueItem> _processedController =
      StreamController<SyncQueueItem>.broadcast();

  Stream<SyncQueueItem> get onItemProcessed => _processedController.stream;

  bool get _supportsPersistentQueue => !kIsWeb;

  Future<void> enqueue({
    required String userScope,
    required String queueType,
    required Map<String, dynamic> payload,
    required String idempotencyKey,
  }) async {
    if (!_supportsPersistentQueue) return;

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    await db.insert(tableName, {
      'user_scope': userScope,
      'queue_type': queueType,
      'payload': jsonEncode(payload),
      'idempotency_key': idempotencyKey,
      'retry_count': 0,
      'next_retry_at': now,
      'created_at': now,
      'updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<List<SyncQueueItem>> getPending({
    required String userScope,
    int limit = 50,
  }) async {
    if (!_supportsPersistentQueue) {
      return const [];
    }

    final db = await DatabaseHelper.instance.database;
    final now = DateTime.now().toIso8601String();

    final rows = await db.query(
      tableName,
      where: 'user_scope = ? AND next_retry_at <= ?',
      whereArgs: [userScope, now],
      orderBy: 'created_at ASC',
      limit: limit,
    );

    return rows
        .map(
          (row) => SyncQueueItem(
            id: row['id'] as int,
            userScope: row['user_scope'] as String,
            queueType: row['queue_type'] as String,
            payload: jsonDecode(row['payload'] as String) as Map<String, dynamic>,
            idempotencyKey: row['idempotency_key'] as String,
            retryCount: row['retry_count'] as int,
            nextRetryAt: DateTime.parse(row['next_retry_at'] as String),
          ),
        )
        .toList();
  }

  Future<void> processPending({
    required String userScope,
    required Future<void> Function(SyncQueueItem item) processor,
    int limit = 50,
  }) async {
    final pending = await getPending(userScope: userScope, limit: limit);
    for (final item in pending) {
      try {
        await processor(item);
        await _markDone(item.id);
        _processedController.add(item);
      } catch (_) {
        await _scheduleRetry(item);
      }
    }
  }

  Future<void> clearUserScope(String userScope) async {
    if (!_supportsPersistentQueue) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(tableName, where: 'user_scope = ?', whereArgs: [userScope]);
  }

  Future<void> clearAll() async {
    if (!_supportsPersistentQueue) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(tableName);
  }

  Future<void> _markDone(int id) async {
    if (!_supportsPersistentQueue) return;

    final db = await DatabaseHelper.instance.database;
    await db.delete(tableName, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> _scheduleRetry(SyncQueueItem item) async {
    if (!_supportsPersistentQueue) return;

    final db = await DatabaseHelper.instance.database;
    final nextRetry = _computeBackoff(item.retryCount + 1);

    await db.update(
      tableName,
      {
        'retry_count': item.retryCount + 1,
        'next_retry_at': nextRetry.toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  DateTime _computeBackoff(int retryCount) {
    const baseSeconds = 5;
    const maxSeconds = 300;
    final factor = pow(2, retryCount.clamp(0, 8)).toInt();
    final backoff = min(maxSeconds, baseSeconds * factor);
    return DateTime.now().add(Duration(seconds: backoff));
  }

  static Future<void> createTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  user_scope TEXT NOT NULL,
  queue_type TEXT NOT NULL,
  payload TEXT NOT NULL,
  idempotency_key TEXT NOT NULL UNIQUE,
  retry_count INTEGER NOT NULL DEFAULT 0,
  next_retry_at TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
)
''');

    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_scope ON $tableName (user_scope)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_sync_queue_retry ON $tableName (next_retry_at)',
    );
  }
}
