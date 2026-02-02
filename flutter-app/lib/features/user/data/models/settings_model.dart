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
  });

  factory SettingsModel.fromJson(Map<String, dynamic> json) {
    return SettingsModel(
      id: json['id'] as int? ?? 0,
      userId: json['userId'] as String,
      notificationEnabled: _parseBool(json['notificationEnabled']),
      notificationTime: json['notificationTime'] as String? ?? "09:00",
      theme: json['theme'] as String? ?? "system",
      language: json['language'] as String? ?? "en",
      soundEnabled: _parseBool(json['soundEnabled']),
      dailyGoalXP: json['dailyGoalXP'] as int? ?? 50,
    );
  }

  /// Helper to parse bool from int or bool
  static bool _parseBool(dynamic value) {
    if (value == null) return true;
    if (value is bool) return value;
    if (value is int) return value == 1;
    return true;
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
    );
  }
}
