import 'package:lexilingo_app/core/network/api_client.dart';
import '../models/settings_model.dart';
import '../../domain/entities/settings.dart';

class SettingsRemoteDataSource {
  final ApiClient apiClient;

  SettingsRemoteDataSource({required this.apiClient});

  Future<SettingsModel> getReminderPreferences(String userId) async {
    final response = await apiClient.get('/users/me/reminder-preferences');
    return SettingsModel.fromJson({...response, 'userId': userId});
  }

  Future<SettingsModel> updateReminderPreferences(Settings settings) async {
    final response = await apiClient.putEnvelope<Map<String, dynamic>>(
      '/users/me/reminder-preferences',
      body: {
        'enabled': settings.notificationEnabled,
        'push_enabled': settings.pushReminderEnabled,
        'email_enabled': settings.emailReminderEnabled,
        'reminder_time_local': settings.notificationTime,
        'timezone': settings.reminderTimezone,
        'min_due_count': settings.reminderMinDueCount,
        'email_cadence_days': settings.emailCadenceDays,
      },
      fromJson: (json) => json as Map<String, dynamic>,
    );
    return SettingsModel.fromJson({
      ...response.data,
      'userId': settings.userId,
    });
  }
}
