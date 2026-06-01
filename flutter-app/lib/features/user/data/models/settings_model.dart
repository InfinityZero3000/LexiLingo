import '../../domain/entities/settings.dart';

class SettingsModel extends Settings {
  const SettingsModel({
    required super.id,
    required super.userId,
    super.notificationEnabled,
    super.notificationTime,
    super.theme,
    super.language,
    super.soundEnabled,
    super.dailyGoalXP,
    super.pushReminderEnabled,
    super.emailReminderEnabled,
    super.emailCadenceDays,
    super.reminderMinDueCount,
    super.reminderTimezone,
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      id: json['id'] as int? ?? 0,
      userId: json['userId'] as String? ?? json['user_id'] as String? ?? '',
      notificationEnabled: _parseBool(
        json['notificationEnabled'] ?? json['enabled'],
        defaultValue: true,
      ),
      notificationTime:
          json['notificationTime'] as String? ??
          json['reminder_time_local'] as String? ??
          "09:00",
      theme: json['theme'] as String? ?? "system",
      language: json['language'] as String? ?? "en",
      soundEnabled: _parseBool(json['soundEnabled'], defaultValue: true),
      dailyGoalXP: json['dailyGoalXP'] as int? ?? 50,
      pushReminderEnabled: _parseBool(
        json['pushReminderEnabled'] ?? json['push_enabled'],
        defaultValue: true,
      ),
      emailReminderEnabled: _parseBool(
        json['emailReminderEnabled'] ?? json['email_enabled'],
        defaultValue: false,
      ),
      emailCadenceDays:
          json['emailCadenceDays'] as int? ??
          json['email_cadence_days'] as int? ??
          7,
      reminderMinDueCount:
          json['reminderMinDueCount'] as int? ??
          json['min_due_count'] as int? ??
          1,
      reminderTimezone:
          json['reminderTimezone'] as String? ??
          json['timezone'] as String? ??
          "Asia/Ho_Chi_Minh",
    );
  }

  /// Helper to parse bool from int or bool
  static bool _parseBool(dynamic value, {required bool defaultValue}) {
    if (value == null) return defaultValue;
    if (value is bool) return value;
    if (value is int) return value == 1;
    return defaultValue;
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'userId': userId,
      'notificationEnabled': notificationEnabled ? 1 : 0,
      'notificationTime': notificationTime,
      'theme': theme,
      'language': language,
      'soundEnabled': soundEnabled ? 1 : 0,
      'dailyGoalXP': dailyGoalXP,
      'pushReminderEnabled': pushReminderEnabled ? 1 : 0,
      'emailReminderEnabled': emailReminderEnabled ? 1 : 0,
      'emailCadenceDays': emailCadenceDays,
      'reminderMinDueCount': reminderMinDueCount,
      'reminderTimezone': reminderTimezone,
    };
  }

  factory SettingsModel.fromEntity(Settings settings) {
    return SettingsModel(
      id: settings.id,
      userId: settings.userId,
      notificationEnabled: settings.notificationEnabled,
      notificationTime: settings.notificationTime,
      theme: settings.theme,
      language: settings.language,
      soundEnabled: settings.soundEnabled,
      dailyGoalXP: settings.dailyGoalXP,
      pushReminderEnabled: settings.pushReminderEnabled,
      emailReminderEnabled: settings.emailReminderEnabled,
      emailCadenceDays: settings.emailCadenceDays,
      reminderMinDueCount: settings.reminderMinDueCount,
      reminderTimezone: settings.reminderTimezone,
    );
  }
}
