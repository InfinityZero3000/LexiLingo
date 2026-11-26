import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

/// SharedPreferences holding what is stored right now.
///
/// On the web every tab caches its own copy of one shared localStorage. Reading
/// the cache and writing the result back erases whatever another tab stored in
/// between, so use this for any read that decides a write: tokens, queues of
/// unsent data, and lists that exist only on this device.
Future<SharedPreferences> freshPreferences() async {
  final prefs = await SharedPreferences.getInstance();
  if (kIsWeb) await prefs.reload();
  return prefs;
}
