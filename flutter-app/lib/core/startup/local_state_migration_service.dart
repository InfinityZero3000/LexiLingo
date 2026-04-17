import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../../features/auth/data/datasources/token_storage.dart';

/// One-time local-state wipe for breaking cache/schema transitions.
class LocalStateMigrationService {
  static const int _wipeVersion = 1;
  static const String _wipeVersionKey = 'local_state_wipe_version';

  Future<void> runIfNeeded() async {
    final prefs = await SharedPreferences.getInstance();
    final appliedVersion = prefs.getInt(_wipeVersionKey) ?? 0;
    if (appliedVersion >= _wipeVersion) {
      return;
    }

    // Clear tokens, secure storage, encrypted cache, and sync queue.
    await TokenStorage().clearAll();

    // Drop legacy local SQLite state so new schema starts clean.
    if (!kIsWeb) {
      final dbPath = await getDatabasesPath();
      final path = join(dbPath, 'lexilingo.db');
      await deleteDatabase(path);
    }

    // Clear old SharedPreferences cache keys from previous releases.
    await prefs.clear();
    await prefs.setInt(_wipeVersionKey, _wipeVersion);
  }
}
