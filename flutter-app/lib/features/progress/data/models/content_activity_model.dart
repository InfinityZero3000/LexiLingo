/// Content Activity Model — maps GET /xp/content-activity.
library;

import 'package:lexilingo_app/features/progress/domain/entities/content_activity_entity.dart';

class ContentSourceActivityModel extends ContentSourceActivityEntity {
  const ContentSourceActivityModel({
    required super.source,
    required super.sessions,
    required super.minutes,
    required super.tracksMinutes,
    required super.xpEarned,
    super.lastActiveAt,
  });

  factory ContentSourceActivityModel.fromJson(Map<String, dynamic> json) {
    final lastActive = json['last_active_at'] as String?;
    return ContentSourceActivityModel(
      source: json['source'] as String? ?? '',
      sessions: json['sessions'] as int? ?? 0,
      minutes: json['minutes'] as int? ?? 0,
      tracksMinutes: json['tracks_minutes'] as bool? ?? false,
      xpEarned: json['xp_earned'] as int? ?? 0,
      lastActiveAt: lastActive == null ? null : DateTime.tryParse(lastActive),
    );
  }
}

class ContentActivityModel extends ContentActivityEntity {
  const ContentActivityModel({
    required super.days,
    required super.totalMinutes,
    required super.totalSessions,
    required super.totalXp,
    required super.bySource,
  });

  factory ContentActivityModel.fromJson(Map<String, dynamic> json) {
    final sources = (json['by_source'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ContentSourceActivityModel.fromJson)
        .toList(growable: false);

    return ContentActivityModel(
      days: json['days'] as int? ?? 7,
      totalMinutes: json['total_minutes'] as int? ?? 0,
      totalSessions: json['total_sessions'] as int? ?? 0,
      totalXp: json['total_xp'] as int? ?? 0,
      bySource: sources,
    );
  }
}
