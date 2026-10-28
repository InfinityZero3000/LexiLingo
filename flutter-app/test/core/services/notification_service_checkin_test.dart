import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/localization.dart';
// ignore: implementation_imports
import 'package:easy_localization/src/translations.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channel = MethodChannel('dexterous.com/flutter/local_notifications');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<MethodCall> calls;

  setUp(() {
    EasyLocalization.logger.enableLevels = [];
    final vi = jsonDecode(File('assets/i18n/vi.json').readAsStringSync());
    Localization.load(const Locale('vi'), translations: Translations(vi));

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, (call) async {
          calls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'requestNotificationsPermission') return true;
          return null;
        });
  });

  tearDown(() => debugDefaultTargetPlatformOverride = null);

  List<Map> scheduled() => calls
      .where((c) => c.method == 'zonedSchedule')
      .map((c) => c.arguments as Map)
      .toList();

  // The plugin validates scheduledDate against the real clock, so the fixture
  // "today" is tomorrow: every slot below stays in the future whenever the
  // suite runs.
  final real = DateTime.now();
  DateTime day(int offset, int hour, int minute) =>
      DateTime(real.year, real.month, real.day + 1 + offset, hour, minute);
  DateTime scheduledAt(Map m) =>
      DateTime.parse(m['scheduledDateTimeISO8601'] as String).toLocal();

  test('streak at risk: today fires at the chosen local time, quoting the streak', () async {
    await NotificationService().scheduleCheckinReminders(
      const TimeOfDay(hour: 20, minute: 30),
      currentStreak: 4,
      longestStreak: 9,
      doneToday: false,
      now: day(0, 9, 0),
    );

    final s = scheduled();
    expect(s, hasLength(NotificationService.checkinDays));
    final first = s.first;
    expect(
      scheduledAt(first),
      day(0, 20, 30),
      reason: 'wall-clock time must survive tz.local being UTC',
    );
    expect(first['title'], 'Chuỗi 4 ngày vẫn chờ bạn hôm nay');
    expect(first['payload'], 'checkin');
    final android = first['platformSpecifics'] as Map;
    expect(android['scheduleMode'], 'inexactAllowWhileIdle',
        reason: 'exact mode throws without SCHEDULE_EXACT_ALARM');
    expect(android['channelId'], 'checkin_reminder_channel');

    // Later slots never quote a count and never repeat the day before.
    for (var i = 1; i < s.length; i++) {
      expect(s[i]['title'], isNot(contains('4')));
      expect(s[i]['title'], isNot(s[i - 1]['title']));
    }
    expect(s.map((m) => m['id']).toSet(), hasLength(s.length));
  });

  test('already checked in today: first reminder moves to tomorrow', () async {
    await NotificationService().scheduleCheckinReminders(
      const TimeOfDay(hour: 20, minute: 0),
      currentStreak: 3,
      longestStreak: 3,
      doneToday: true,
      now: day(0, 9, 0),
    );

    final first = scheduled().first;
    expect(scheduledAt(first), day(1, 20, 0));
    expect(first['title'], 'Hôm nay là ngày thứ 4');
  });

  test('time already passed today rolls to tomorrow', () async {
    await NotificationService().scheduleCheckinReminders(
      const TimeOfDay(hour: 8, minute: 0),
      currentStreak: 0,
      longestStreak: 0,
      doneToday: false,
      now: day(0, 9, 0),
    );
    expect(scheduledAt(scheduled().first), day(1, 8, 0));
  });

  test('a slot that only fires after the streak lapsed does not quote it', () async {
    await NotificationService().scheduleCheckinReminders(
      const TimeOfDay(hour: 8, minute: 0),
      currentStreak: 4,
      longestStreak: 9,
      doneToday: false,
      now: day(0, 9, 0),
    );
    final first = scheduled().first;
    expect(scheduledAt(first), day(1, 8, 0));
    expect(first['title'], isNot('Chuỗi 4 ngày vẫn chờ bạn hôm nay'));
    expect(first['title'], isNot(contains('4')));
  });

  test('lead message picks the situation, not a fixed line', () {
    String key(int s, int l, bool done) =>
        NotificationService.checkinLeadMessage(s, l, doneToday: done).key;
    expect(key(6, 6, false), 'milestone');
    expect(key(6, 6, true), 'milestone');
    expect(key(4, 9, false), 'atRisk');
    expect(key(4, 9, true), 'keepGoing');
    expect(key(0, 12, false), 'comeback');
    expect(key(0, 1, false), 'fresh');
  });

  test('refresh is a no-op while switched off, and does not touch review id 0',
      () async {
    SharedPreferences.setMockInitialValues({});
    final service = NotificationService();
    await service.refreshCheckinReminders(
      currentStreak: 2, longestStreak: 2, doneToday: false);
    expect(scheduled(), isEmpty);

    SharedPreferences.setMockInitialValues({
      NotificationService.checkinEnabledKey: true,
      NotificationService.checkinHourKey: 23,
      NotificationService.checkinMinuteKey: 59,
    });
    await service.refreshCheckinReminders(
      currentStreak: 2, longestStreak: 2, doneToday: true);
    final ids = scheduled().map((m) => m['id'] as int);
    expect(ids, isNot(contains(0)));
    final cancelled = calls.where((c) => c.method == 'cancel');
    expect(cancelled.map((c) => (c.arguments as Map)['id']), isNot(contains(0)));
  });
}
