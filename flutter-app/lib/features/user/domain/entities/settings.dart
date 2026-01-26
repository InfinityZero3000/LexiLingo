class Settings {
  final int id;
  final String userId;
  final bool notificationEnabled;
  final String notificationTime; // "HH:MM" format
  final String theme; // "light", "dark", "system"
  final String language; // "en", "vi", etc.
  final bool soundEnabled;
  final int dailyGoalXP;

  const Settings({
    required this.id,
    required this.userId,
    this.notificationEnabled = true,
    this.notificationTime = "09:00",
    this.theme = "system",
    this.language = "en",
    this.soundEnabled = true,
    this.dailyGoalXP = 50,
  });

  Settings copyWith({
    int? id,
    String? userId,
    bool? notificationEnabled,
    String? notificationTime,
    String? theme,
    String? language,
    bool? soundEnabled,
    int? dailyGoalXP,
  }) {
    return Settings(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      notificationEnabled: notificationEnabled ?? this.notificationEnabled,
      notificationTime: notificationTime ?? this.notificationTime,
      theme: theme ?? this.theme,
      language: language ?? this.language,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      dailyGoalXP: dailyGoalXP ?? this.dailyGoalXP,
    );
  }
}
