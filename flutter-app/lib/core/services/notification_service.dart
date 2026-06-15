import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:lexilingo_app/core/services/app_navigation_service.dart';

class NotificationService {
  static const int _dailyReminderId = 0;
  static const String _reviewRoute = '/vocabulary/review';

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;

    tz.initializeTimeZones();
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

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

  Future<void> scheduleDailyReminder(TimeOfDay time, {int dueCount = 0}) async {
    await ensureInitialized();
    final body = dueCount > 0
        ? 'Bạn có $dueCount từ cần ôn tập hôm nay!'
        : 'Đã đến giờ ôn từ vựng – giữ vững streak của bạn!';
    await flutterLocalNotificationsPlugin.zonedSchedule(
      _dailyReminderId,
      'Ôn tập từ vựng',
      body,
      _nextInstanceOfTime(time.hour, time.minute),
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel',
          'Nhắc nhở hàng ngày',
          channelDescription: 'Nhắc bạn ôn tập từ vựng mỗi ngày',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'vocabulary_review',
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: _reviewRoute,
    );
  }

  Future<void> showImmediateReviewReminder(int dueCount) async {
    await ensureInitialized();
    await flutterLocalNotificationsPlugin.show(
      _dailyReminderId + 1,
      'Ôn tập từ vựng',
      'Bạn có $dueCount từ đến hạn ôn tập!',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder_channel',
          'Nhắc nhở hàng ngày',
          channelDescription: 'Nhắc bạn ôn tập từ vựng mỗi ngày',
          importance: Importance.high,
        ),
        iOS: DarwinNotificationDetails(
          categoryIdentifier: 'vocabulary_review',
        ),
      ),
      payload: _reviewRoute,
    );
  }

  Future<void> cancelDailyReminder() async {
    await ensureInitialized();
    await flutterLocalNotificationsPlugin.cancel(_dailyReminderId);
  }

  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }
}

@pragma('vm:entry-point')
void _onNotificationTapBackground(NotificationResponse response) {
  // Background tap is handled on app resume via getNotificationAppLaunchDetails.
}
