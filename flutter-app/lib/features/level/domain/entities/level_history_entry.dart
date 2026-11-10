import 'package:equatable/equatable.dart';

/// One CEFR level change from `GET /proficiency/history`.
///
/// The server's `reason` is a fixed English sentence, so it is deliberately not
/// modelled: showing it would put English in every locale.
class LevelHistoryEntry extends Equatable {
  final String previousLevel;
  final String newLevel;
  final bool isPromotion;
  final DateTime triggeredAt;

  const LevelHistoryEntry({
    required this.previousLevel,
    required this.newLevel,
    required this.isPromotion,
    required this.triggeredAt,
  });

  @override
  List<Object?> get props => [
    previousLevel,
    newLevel,
    isPromotion,
    triggeredAt,
  ];
}

/// Parses the history response into entries ordered oldest first.
///
/// Rows that miss a level or carry an unreadable date are skipped rather than
/// failing the whole timeline. The response itself is newest first.
List<LevelHistoryEntry> parseLevelHistory(Map<String, dynamic> json) {
  final raw = json['history'];
  if (raw is! List) return const [];

  final entries = <LevelHistoryEntry>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final previous = item['previous_level'];
    final next = item['new_level'];
    final at = DateTime.tryParse('${item['triggered_at']}');
    if (previous is! String || next is! String || at == null) continue;
    entries.add(
      LevelHistoryEntry(
        previousLevel: previous,
        newLevel: next,
        isPromotion: item['change_type'] != 'demotion',
        triggeredAt: at.toLocal(),
      ),
    );
  }
  entries.sort((a, b) => a.triggeredAt.compareTo(b.triggeredAt));
  return entries;
}
