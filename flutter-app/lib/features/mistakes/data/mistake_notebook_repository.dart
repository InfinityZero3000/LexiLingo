import 'dart:convert';

import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MistakeNotebookRepository {
  static const _storageKey = 'mistake_notebook_entries_v1';

  final Future<SharedPreferences> Function() _prefsFactory;

  const MistakeNotebookRepository({
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  Future<List<MistakeNotebookEntry>> getEntries() async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString(_storageKey);
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

  Future<void> saveMistake(MistakeNotebookEntry entry) async {
    final entries = (await getEntries()).toList();
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
  }

  Future<void> markReviewed(String id) async {
    final entries = (await getEntries()).toList();
    final index = entries.indexWhere((entry) => entry.id == id);
    if (index == -1) return;

    entries[index] = entries[index].copyWith(
      reviewedAt: DateTime.now(),
      reviewCount: entries[index].reviewCount + 1,
    );
    await _saveEntries(sortMistakes(entries));
  }

  Future<void> delete(String id) async {
    final entries = (await getEntries()).toList();
    entries.removeWhere((entry) => entry.id == id);
    await _saveEntries(entries);
  }

  Future<void> clearReviewed() async {
    final entries = (await getEntries()).toList();
    entries.removeWhere((entry) => entry.isReviewed);
    await _saveEntries(entries);
  }

  Future<void> _saveEntries(List<MistakeNotebookEntry> entries) async {
    final prefs = await _prefsFactory();
    await prefs.setString(
      _storageKey,
      jsonEncode(entries.map((entry) => entry.toJson()).toList()),
    );
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
