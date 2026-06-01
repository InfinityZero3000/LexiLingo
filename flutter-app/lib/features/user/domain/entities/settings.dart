class Settings {
  final int id;
  final String userId;
  final bool notificationEnabled;
  final String notificationTime; // "HH:MM" format
  final String theme; // "light", "dark", "system"
  final String language; // "en", "vi", etc.
  final bool soundEnabled;
  final int dailyGoalXP;
  final bool pushReminderEnabled;
  final bool emailReminderEnabled;
  final int emailCadenceDays;
  final int reminderMinDueCount;
  final String reminderTimezone;

  const Settings({
    required this.id,
    required this.userId,
    this.notificationEnabled = true,
    this.notificationTime = "09:00",
    this.theme = "system",
    this.language = "en",
    this.soundEnabled = true,
    this.dailyGoalXP = 50,
    this.pushReminderEnabled = true,
    this.emailReminderEnabled = false,
    this.emailCadenceDays = 7,
    this.reminderMinDueCount = 1,
    this.reminderTimezone = "Asia/Ho_Chi_Minh",
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
    bool? pushReminderEnabled,
    bool? emailReminderEnabled,
    int? emailCadenceDays,
    int? reminderMinDueCount,
    String? reminderTimezone,
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
      pushReminderEnabled: pushReminderEnabled ?? this.pushReminderEnabled,
      emailReminderEnabled: emailReminderEnabled ?? this.emailReminderEnabled,
      emailCadenceDays: emailCadenceDays ?? this.emailCadenceDays,
      reminderMinDueCount: reminderMinDueCount ?? this.reminderMinDueCount,
      reminderTimezone: reminderTimezone ?? this.reminderTimezone,
    );
  }
}
