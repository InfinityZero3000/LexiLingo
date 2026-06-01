import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/user/data/models/settings_model.dart';

void main() {
  group('SettingsModel reminder fields', () {
    test('parses old local payload with safe defaults', () {
      final model = SettingsModel.fromJson({
        'id': 1,
        'userId': 'user-1',
        'notificationEnabled': 1,
        'notificationTime': '09:00',
      });

      expect(model.pushReminderEnabled, isTrue);
      expect(model.emailReminderEnabled, isFalse);
      expect(model.emailCadenceDays, 7);
      expect(model.reminderMinDueCount, 1);
      expect(model.reminderTimezone, 'Asia/Ho_Chi_Minh');
    });

    test('parses backend snake case reminder payload', () {
      final model = SettingsModel.fromJson({
        'userId': 'user-1',
        'enabled': true,
        'push_enabled': false,
        'email_enabled': true,
        'reminder_time_local': '20:30',
        'timezone': 'Asia/Ho_Chi_Minh',
        'min_due_count': 3,
        'email_cadence_days': 14,
      });

      expect(model.notificationEnabled, isTrue);
      expect(model.notificationTime, '20:30');
      expect(model.pushReminderEnabled, isFalse);
      expect(model.emailReminderEnabled, isTrue);
      expect(model.emailCadenceDays, 14);
      expect(model.reminderMinDueCount, 3);
    });
  });
}
