/// What the learner was credited for on the library, podcast, video and news
/// surfaces.
///
/// Read server-side off the immutable XP transaction rows, so this is exactly
/// what the system counted — a source sitting at zero means nothing registered,
/// not that the report is incomplete.
library;

class ContentSourceActivityEntity {
  const ContentSourceActivityEntity({
    required this.source,
    required this.sessions,
    required this.minutes,
    required this.tracksMinutes,
    required this.xpEarned,
    this.lastActiveAt,
  });

  /// `youtube` | `podcast` | `news` | `book`
  final String source;

  /// Credited activities: videos watched in chunks, episodes, quizzes passed.
  final int sessions;

  /// Reported time, capped per activity. Always 0 when [tracksMinutes] is false.
  final int minutes;

  /// Whether this source is credited by time or per activity.
  ///
  /// News and books are credited on the quiz — comprehension, not screen time —
  /// so showing "0 minutes" for them would read as a broken counter. Render
  /// [sessions] instead.
  final bool tracksMinutes;

  final int xpEarned;
  final DateTime? lastActiveAt;

  bool get hasActivity => sessions > 0;
}

class ContentActivityEntity {
  const ContentActivityEntity({
    required this.days,
    required this.totalMinutes,
    required this.totalSessions,
    required this.totalXp,
    required this.bySource,
  });

  final int days;
  final int totalMinutes;
  final int totalSessions;
  final int totalXp;
  final List<ContentSourceActivityEntity> bySource;

  static const empty = ContentActivityEntity(
    days: 7,
    totalMinutes: 0,
    totalSessions: 0,
    totalXp: 0,
    bySource: [],
  );

  bool get isEmpty => totalSessions == 0;
}
