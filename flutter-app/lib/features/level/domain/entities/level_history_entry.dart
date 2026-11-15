import 'package:equatable/equatable.dart';

/// One CEFR level change from `GET /proficiency/history`.
///
/// The server's `reason` is a fixed English sentence, so it is deliberately not
/// modelled: showing it would put English in every locale.
class LevelHistoryEntry extends Equatable {
  final String previousLevel;
  final String newLevel;
  final bool isPromotion;

  /// The first placement test, as opposed to a later level change.
  final bool isInitial;

  /// The learner picked this working level; no test was involved.
  final bool isSelfSet;
  final DateTime triggeredAt;

  const LevelHistoryEntry({
    required this.previousLevel,
    required this.newLevel,
    required this.isPromotion,
    this.isInitial = false,
    this.isSelfSet = false,
    required this.triggeredAt,
  });

  @override
  List<Object?> get props => [
    previousLevel,
    newLevel,
    isPromotion,
    isInitial,
    isSelfSet,
    triggeredAt,
  ];
}

/// Parses the history response into entries ordered oldest first.
///
/// Rows that miss a level, carry an unreadable date or record no change
/// (same level before and after) are skipped rather than failing the whole
/// timeline. The response itself is newest first.
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
    if (previous == next) continue;
    entries.add(
      LevelHistoryEntry(
        previousLevel: previous,
        newLevel: next,
        // A self-set can go either way; its direction is in the levels.
        isPromotion: item['change_type'] == 'self_set'
            ? _cefrIndex(next) > _cefrIndex(previous)
            : item['change_type'] != 'demotion',
        isInitial: item['change_type'] == 'initial',
        isSelfSet: item['change_type'] == 'self_set',
        triggeredAt: at.toLocal(),
      ),
    );
  }
  entries.sort((a, b) => a.triggeredAt.compareTo(b.triggeredAt));
  return entries;
}

int _cefrIndex(String level) =>
    const ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'].indexOf(level.toUpperCase());
