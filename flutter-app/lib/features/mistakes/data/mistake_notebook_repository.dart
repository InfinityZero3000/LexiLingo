import 'dart:convert';

import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_remote_datasource.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MistakeNotebookRepository {
  static const _storageKey = 'mistake_notebook_entries_v1';
  static const _pendingOpsKey = 'mistake_notebook_pending_ops_v1';

  final Future<SharedPreferences> Function() _prefsFactory;
  final MistakeNotebookRemoteDataSource? _remoteDataSource;
  final bool _syncEnabled;

  const MistakeNotebookRepository({
    Future<SharedPreferences> Function()? prefsFactory,
    MistakeNotebookRemoteDataSource? remoteDataSource,
    bool syncEnabled = true,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
       _remoteDataSource = remoteDataSource,
       _syncEnabled = syncEnabled;

  Future<List<MistakeNotebookEntry>> getEntries() async {
    final localEntries = await _getLocalEntries();
    final remote = _remote;
    if (remote == null) return localEntries;

    try {
      await _flushPendingOps(remote);
      final pendingIds = await _pendingEntryIds();
      final remoteEntries = (await remote.getEntries(
        status: 'all',
      )).where((entry) => !pendingIds.contains(entry.id)).toList();
      final merged = _mergeEntries(localEntries, remoteEntries);
      await _saveEntries(merged);
      return sortMistakes(merged);
    } catch (_) {
      return localEntries;
    }
  }

  Future<void> saveMistake(MistakeNotebookEntry entry) async {
    final entries = (await _getLocalEntries()).toList();
    final index = entries.indexWhere((item) => item.id == entry.id);

    final nextEntry = index == -1
        ? entry
        : entry.copyWith(
            reviewCount: entries[index].reviewCount,
            clearReviewedAt: true,
          );

    if (index == -1) {
      entries.add(nextEntry);
    } else {
      entries[index] = nextEntry;
    }

    await _saveEntries(sortMistakes(entries));
    await _syncOrQueue({'type': 'upsert', 'entry': nextEntry.toJson()});
  }

  Future<void> markReviewed(String id) async {
    final entries = (await _getLocalEntries()).toList();
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return;

    entries[index] = entries[index].copyWith(
      reviewedAt: DateTime.now(),
      reviewCount: entries[index].reviewCount + 1,
    );
    await _saveEntries(sortMistakes(entries));
    await _syncOrQueue({'type': 'review', 'id': id});
  }

  Future<void> delete(String id) async {
    final entries = (await _getLocalEntries()).toList();
    entries.removeWhere((entry) => entry.id == id);
    await _saveEntries(entries);
    await _syncOrQueue({'type': 'delete', 'id': id});
  }

  Future<void> clearReviewed() async {
    final entries = (await _getLocalEntries()).toList();
    final reviewedIds = entries
        .where((entry) => entry.isReviewed)
        .map((entry) => entry.id)
        .toList();
    entries.removeWhere((entry) => entry.isReviewed);
    await _saveEntries(entries);

    for (final id in reviewedIds) {
      await _syncOrQueue({'type': 'delete', 'id': id});
    }
  }

  MistakeNotebookRemoteDataSource? get _remote {
    if (!_syncEnabled) return null;
    if (_remoteDataSource != null) return _remoteDataSource;
    if (!sl.isRegistered<ApiClient>()) return null;
    return ApiMistakeNotebookRemoteDataSource(apiClient: sl<ApiClient>());
  }

  Future<List<MistakeNotebookEntry>> _getLocalEntries() async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString(await _scopedKey(_storageKey));
    if (raw == null || raw.isEmpty) return const [];

    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return sortMistakes(
        decoded
            .whereType<Map<String, dynamic>>()
            .map(MistakeNotebookEntry.fromJson)
            .where((entry) => entry.id.isNotEmpty)
            .toList(),
      );
    } catch (_) {
      return const [];
    }
  }

  Future<void> _saveEntries(List<MistakeNotebookEntry> entries) async {
    final prefs = await _prefsFactory();
    await prefs.setString(
      await _scopedKey(_storageKey),
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
  }

  Future<void> _syncOrQueue(Map<String, dynamic> op) async {
    final remote = _remote;
    if (remote == null) {
      await _queuePendingOp(op);
      return;
    }

    try {
      await _flushPendingOps(remote);
      await _applyRemoteOp(remote, op);
    } catch (_) {
      await _queuePendingOp(op);
    }
  }

  Future<void> _flushPendingOps(MistakeNotebookRemoteDataSource remote) async {
    final prefs = await _prefsFactory();
    final pendingOpsKey = await _scopedKey(_pendingOpsKey);
    final ops = _decodePendingOps(prefs.getString(pendingOpsKey));
    if (ops.isEmpty) return;

    final remaining = <Map<String, dynamic>>[];
    for (var index = 0; index < ops.length; index++) {
      final op = ops[index];
      try {
        await _applyRemoteOp(remote, op);
      } catch (_) {
        remaining.add(op);
        remaining.addAll(ops.skip(index + 1));
        break;
      }
    }

    await prefs.setString(pendingOpsKey, jsonEncode(remaining));
  }

  Future<void> _queuePendingOp(Map<String, dynamic> op) async {
    final prefs = await _prefsFactory();
    final pendingOpsKey = await _scopedKey(_pendingOpsKey);
    final ops = _decodePendingOps(prefs.getString(pendingOpsKey));
    ops.add(op);
    await prefs.setString(pendingOpsKey, jsonEncode(ops));
  }

  Future<void> _applyRemoteOp(
    MistakeNotebookRemoteDataSource remote,
    Map<String, dynamic> op,
  ) async {
    switch (op['type']) {
      case 'upsert':
        final rawEntry = op['entry'];
        if (rawEntry is Map<String, dynamic>) {
          await remote.saveMistake(MistakeNotebookEntry.fromJson(rawEntry));
        }
        break;
      case 'review':
        final id = op['id'] as String?;
        if (id != null && id.isNotEmpty) await remote.markReviewed(id);
        break;
      case 'delete':
        final id = op['id'] as String?;
        if (id != null && id.isNotEmpty) await remote.delete(id);
        break;
    }
  }

  List<Map<String, dynamic>> _decodePendingOps(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded.whereType<Map<String, dynamic>>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<Set<String>> _pendingEntryIds() async {
    final prefs = await _prefsFactory();
    final ops = _decodePendingOps(
      prefs.getString(await _scopedKey(_pendingOpsKey)),
    );
    final ids = <String>{};
    for (final op in ops) {
      final id = op['id'] as String?;
      if (id != null && id.isNotEmpty) {
        ids.add(id);
        continue;
      }
      final rawEntry = op['entry'];
      if (rawEntry is Map<String, dynamic>) {
        final entryId = rawEntry['id'] as String?;
        if (entryId != null && entryId.isNotEmpty) ids.add(entryId);
      }
    }
    return ids;
  }

  List<MistakeNotebookEntry> _mergeEntries(
    List<MistakeNotebookEntry> localEntries,
    List<MistakeNotebookEntry> remoteEntries,
  ) {
    final merged = <String, MistakeNotebookEntry>{};
    for (final entry in [...remoteEntries, ...localEntries]) {
      final current = merged[entry.id];
      if (current == null || !entry.createdAt.isBefore(current.createdAt)) {
        merged[entry.id] = entry;
      }
    }
    return sortMistakes(merged.values.toList());
  }

  Future<String> _scopedKey(String baseKey) async {
    final scope = await UserScopeService.getScopeOrDefault();
    if (scope == 'anonymous') return baseKey;
    return '$baseKey:$scope';
  }
}

List<MistakeNotebookEntry> sortMistakes(List<MistakeNotebookEntry> entries) {
  final sorted = [...entries];
  sorted.sort((a, b) {
    if (a.isReviewed != b.isReviewed) {
      return a.isReviewed ? 1 : -1;
    }
    return b.createdAt.compareTo(a.createdAt);
  });
  return sorted;
}
