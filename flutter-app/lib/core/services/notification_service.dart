import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:lexilingo_app/core/services/app_navigation_service.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class NotificationService {
  static const int _dailyReminderId = 0;
  static const String _reviewRoute = '/vocabulary/review';
  static const String _checkinPayload = 'checkin';

  // Monochrome status-bar icon (res/drawable): the colour launcher icon draws
  // as a grey square. The server's pushes name the same icon and channels.
  static const String _androidIcon = 'ic_stat_lexilingo';
  static const String _reviewChannelId = 'daily_reminder_channel';
  static const String _checkinChannelId = 'checkin_reminder_channel';
  // Shared with the server's vocabulary pushes so iOS stacks them together.
  static const String _reviewThread = 'vocabulary_review_reminder';

  static const checkinEnabledKey = 'checkin_reminder_enabled';
  static const checkinHourKey = 'checkin_reminder_hour';
  static const checkinMinuteKey = 'checkin_reminder_minute';

  // ponytail: one-shot slots, re-filled whenever the streak loads. A learner
  // who stays away for a week stops being nudged — intended, not a gap.
  static const int _checkinBaseId = 100;
  static const int checkinDays = 7;
  static const _milestones = [7, 14, 30, 60, 100, 365];
  static const _rotation = ['waiting', 'fiveMinutes', 'oneSentence', 'yourTime', 'fading'];

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings(_androidIcon);

    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings();

    const InitializationSettings initializationSettings =
        InitializationSettings(
          android: initializationSettingsAndroid,
          iOS: initializationSettingsDarwin,
        );

    await flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _onNotificationTap,
      onDidReceiveBackgroundNotificationResponse: _onNotificationTapBackground,
    );

    // Handle notification that launched the app from terminated state.
    // Defer navigation until after the first frame so the navigator is ready.
    final launchDetails = await flutterLocalNotificationsPlugin
        .getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchDetails!.notificationResponse != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _onNotificationTap(launchDetails.notificationResponse!);
      });
    }

    _isInitialized = true;
  }

  void _onNotificationTap(NotificationResponse response) {
    final payload = response.payload ?? '';
    if (payload == _checkinPayload) {
      AppNavigationService.returnToRoot();
      return;
    }
    if (payload == _reviewRoute || payload.isEmpty) {
      AppNavigationService.openRoute(_reviewRoute);
    }
  }

  Future<void> ensureInitialized() async {
    await init();
  }

  Future<bool> requestPermissions() async {
    await ensureInitialized();

    final androidPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final iosPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    final macOsPlugin = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          MacOSFlutterLocalNotificationsPlugin
        >();

    bool granted = true;

    final androidGranted = await androidPlugin
        ?.requestNotificationsPermission();
    if (androidGranted == false) {
      granted = false;
    }

    final iosGranted = await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (iosGranted == false) {
      granted = false;
    }

    final macOsGranted = await macOsPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    if (macOsGranted == false) {
      granted = false;
    }

    return granted;
  }

  /// Creates the Android channels the server's pushes are addressed to.
  ///
  /// A push naming a channel the device does not have lands in FCM's generic
  /// "Miscellaneous" one, where the learner cannot mute it on its own. Called
  /// once translations are loaded, because the names show in system settings.
  Future<void> ensureChannels() async {
    await ensureInitialized();
    final android = flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    try {
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _reviewChannelId,
          'notifications.reviewChannelName'.tr(),
          description: 'notifications.reviewChannelDescription'.tr(),
          importance: Importance.high,
        ),
      );
      await android.createNotificationChannel(
        AndroidNotificationChannel(
          _checkinChannelId,
          'notifications.checkin.channelName'.tr(),
          description: 'notifications.checkin.channelDescription'.tr(),
          importance: Importance.high,
        ),
      );
    } catch (e) {
      // Best effort: a push still arrives in the fallback channel.
      debugPrint('Notification channels not created: $e');
    }
  }

  /// Daily review nudge, used only when the server is not sending pushes.
  ///
  /// It repeats unchanged every day, so it must not quote a count: one taken
  /// when it was scheduled would be stale by the next morning.
  Future<void> scheduleDailyReminder(TimeOfDay time) async {
    await ensureInitialized();
    final title = 'notifications.reviewTitle'.tr();
    final body = 'notifications.reviewBodyStreak'.tr();
    await flutterLocalNotificationsPlugin.zonedSchedule(
      _dailyReminderId,
      title,
      body,
      _nextInstanceOfTime(time.hour, time.minute),
      NotificationDetails(
        android: AndroidNotificationDetails(
          _reviewChannelId,
          'notifications.reviewChannelName'.tr(),
          channelDescription: 'notifications.reviewChannelDescription'.tr(),
          importance: Importance.high,
          category: AndroidNotificationCategory.reminder,
          color: AppColors.primary,
          styleInformation: BigTextStyleInformation(body, contentTitle: title),
        ),
        iOS: const DarwinNotificationDetails(threadIdentifier: _reviewThread),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _reviewRoute,
    );
  }

  Future<void> cancelDailyReminder() async {
    await ensureInitialized();
    await flutterLocalNotificationsPlugin.cancel(_dailyReminderId);
  }

  /// Fills the next [checkinDays] reminder slots, skipping today once the
  /// learner has already checked in so a kept promise is not nagged about.
  Future<void> scheduleCheckinReminders(
    TimeOfDay time, {
    required int currentStreak,
    required int longestStreak,
    required bool doneToday,
    DateTime? now,
  }) async {
    await cancelCheckinReminders();
    final clock = now ?? DateTime.now();
    var day = DateTime(clock.year, clock.month, clock.day, time.hour, time.minute);
    // Today's slot is already gone and nothing was done: by the time the next
    // one fires the streak has lapsed, so it must not quote it.
    final missedToday = !doneToday && !day.isAfter(clock);
    if (doneToday || missedToday) {
      day = DateTime(day.year, day.month, day.day + 1, time.hour, time.minute);
    }
    final quotedStreak = missedToday ? 0 : currentStreak;

    for (var i = 0; i < checkinDays; i++) {
      final at = DateTime(day.year, day.month, day.day + i, time.hour, time.minute);
      // Only the first slot may quote the streak: later ones fire after days
      // we know nothing about, and a wrong count is worse than none.
      final m = i == 0
          ? checkinLeadMessage(quotedStreak, longestStreak, doneToday: doneToday)
          : CheckinMessage(_rotation[(at.difference(DateTime(at.year)).inDays) % _rotation.length]);
      final title = 'notifications.checkin.${m.key}Title'.tr(namedArgs: m.args);
      final body = 'notifications.checkin.${m.key}Body'.tr(namedArgs: m.args);
      final summary = quotedStreak > 0 && i == 0
          ? 'notifications.checkin.streakSummary'.tr(namedArgs: {'count': '$quotedStreak'})
          : null;

      await flutterLocalNotificationsPlugin.zonedSchedule(
        _checkinBaseId + i,
        title,
        body,
        tz.TZDateTime.from(at, tz.local),
        NotificationDetails(
          android: AndroidNotificationDetails(
            _checkinChannelId,
            'notifications.checkin.channelName'.tr(),
            channelDescription: 'notifications.checkin.channelDescription'.tr(),
            importance: Importance.high,
            category: AndroidNotificationCategory.reminder,
            color: AppColors.primary,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: summary,
            ),
          ),
          iOS: DarwinNotificationDetails(
            subtitle: summary,
            threadIdentifier: 'checkin',
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: _checkinPayload,
      );
    }
  }

  Future<void> cancelCheckinReminders() async {
    await ensureInitialized();
    for (var i = 0; i < checkinDays; i++) {
      await flutterLocalNotificationsPlugin.cancel(_checkinBaseId + i);
    }
  }

  /// Re-fills the check-in slots from saved prefs; no-op while switched off.
  Future<void> refreshCheckinReminders({
    required int currentStreak,
    required int longestStreak,
    required bool doneToday,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (!(prefs.getBool(checkinEnabledKey) ?? false)) return;
    await scheduleCheckinReminders(
      TimeOfDay(
        hour: prefs.getInt(checkinHourKey) ?? 12,
        minute: prefs.getInt(checkinMinuteKey) ?? 0,
      ),
      currentStreak: currentStreak,
      longestStreak: longestStreak,
      doneToday: doneToday,
    );
  }

  @visibleForTesting
  static CheckinMessage checkinLeadMessage(
    int streak,
    int longest, {
    required bool doneToday,
  }) {
    // Whether the slot is today (not yet done) or tomorrow (done), the next
    // check-in lands the learner on streak + 1.
    final next = streak + 1;
    if (streak > 0 && _milestones.contains(next)) {
      return CheckinMessage('milestone', {'count': '$next'});
    }
    if (streak > 0 && !doneToday) {
      return CheckinMessage('atRisk', {'count': '$streak'});
    }
    if (streak == 0 && longest >= 3) {
      return CheckinMessage('comeback', {'count': '$longest'});
    }
    if (streak == 0) return const CheckinMessage('fresh');
    return CheckinMessage('keepGoing', {'count': '$next'});
  }

  // tz.local stays UTC (no device-zone lookup here), so build the wall-clock
  // time with DateTime and convert the instant. ponytail: a daily repeat then
  // drifts an hour across DST; resolve the IANA zone if a DST market matters.
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final now = DateTime.now();
    var at = DateTime(now.year, now.month, now.day, hour, minute);
    if (!at.isAfter(now)) {
      at = DateTime(now.year, now.month, now.day + 1, hour, minute);
    }
    return tz.TZDateTime.from(at, tz.local);
  }
}

class CheckinMessage {
  final String key;
  final Map<String, String> args;
  const CheckinMessage(this.key, [this.args = const {}]);
}

@pragma('vm:entry-point')
void _onNotificationTapBackground(NotificationResponse response) {
  // Background tap is handled on app resume via getNotificationAppLaunchDetails.
}
