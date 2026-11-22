import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../domain/entities/streak_entity.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/progress/presentation/theme/progress_palette.dart';

const _kCalendarCellCount = 42;

void showPointsCalendarDialog(BuildContext context, StreakEntity streak) {
  showDialog(
    context: context,
    barrierColor: Theme.of(context).colorScheme.scrim.withValues(alpha: 0.54),
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _PointsCalendarContent(streak: streak),
        ),
      ),
    ),
  );
}

class _PointsCalendarContent extends StatefulWidget {
  final StreakEntity streak;
  const _PointsCalendarContent({required this.streak});

  @override
  State<_PointsCalendarContent> createState() => _PointsCalendarContentState();
}

class _PointsCalendarContentState extends State<_PointsCalendarContent> {
  late DateTime _viewMonth;
  Set<DateTime> _checkinDays = {};

  bool _reminderEnabled = false;
  TimeOfDay _reminderTime = const TimeOfDay(hour: 12, minute: 0);

  @override
  void initState() {
    super.initState();
    _viewMonth = DateTime(DateTime.now().year, DateTime.now().month);
    _buildCheckinDays();
    _loadReminderPrefs();
  }

  void _buildCheckinDays() {
    final set = <DateTime>{};
    final streak = widget.streak;
    if (streak.currentStreak <= 0) {
      _checkinDays = set;
      return;
    }
    // Determine the last active date
    DateTime lastActive;
    if (streak.lastActivityDate != null &&
        streak.lastActivityDate!.isNotEmpty) {
      try {
        lastActive = DateTime.parse(streak.lastActivityDate!);
      } catch (_) {
        lastActive = DateTime.now();
      }
    } else if (streak.isActiveToday) {
      lastActive = DateTime.now();
    } else {
      lastActive = DateTime.now().subtract(const Duration(days: 1));
    }
    // Mark streak.currentStreak consecutive days ending at lastActive
    for (int i = 0; i < streak.currentStreak; i++) {
      final day = lastActive.subtract(Duration(days: i));
      set.add(DateTime(day.year, day.month, day.day));
    }
    _checkinDays = set;
  }

  Future<void> _loadReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _reminderEnabled =
          prefs.getBool(NotificationService.checkinEnabledKey) ?? false;
      final hour = prefs.getInt(NotificationService.checkinHourKey) ?? 12;
      final minute = prefs.getInt(NotificationService.checkinMinuteKey) ?? 0;
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _saveReminderPrefs() async {
    final notificationService = sl<NotificationService>();
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      if (_reminderEnabled && !await notificationService.requestPermissions()) {
        if (!mounted) return;
        setState(() => _reminderEnabled = false);
        messenger?.showSnackBar(
          SnackBar(
            content: Text('notifications.checkin.permissionDenied'.tr()),
          ),
        );
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(
        NotificationService.checkinEnabledKey,
        _reminderEnabled,
      );
      await prefs.setInt(
        NotificationService.checkinHourKey,
        _reminderTime.hour,
      );
      await prefs.setInt(
        NotificationService.checkinMinuteKey,
        _reminderTime.minute,
      );

      if (_reminderEnabled) {
        await notificationService.scheduleCheckinReminders(
          _reminderTime,
          currentStreak: widget.streak.currentStreak,
          longestStreak: widget.streak.longestStreak,
          doneToday: widget.streak.isActiveToday,
        );
      } else {
        await notificationService.cancelCheckinReminders();
      }
    } catch (e) {
      debugPrint('Check-in reminder failed: $e');
      if (!mounted) return;
      setState(() => _reminderEnabled = false);
      messenger?.showSnackBar(
        SnackBar(content: Text('notifications.checkin.scheduleFailed'.tr())),
      );
    }
  }

  void _prevMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month - 1);
    });
  }

  void _nextMonth() {
    setState(() {
      _viewMonth = DateTime(_viewMonth.year, _viewMonth.month + 1);
    });
  }

  bool _isCheckin(DateTime day) {
    return _checkinDays.contains(DateTime(day.year, day.month, day.day));
  }

  bool _isToday(DateTime day) {
    final now = DateTime.now();
    return day.year == now.year && day.month == now.month && day.day == now.day;
  }

  bool _isFuture(DateTime day) {
    final now = DateTime.now();
    return day.isAfter(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : ProgressPalette.calendarCream;
    final cardBg = Theme.of(context).colorScheme.surface;

    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        color: bg,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeader(context, isDark),
              _buildCalendar(isDark, cardBg),
              const SizedBox(height: AppSpacing.md),
              _buildReminderSection(isDark),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
      child: Row(
        children: [
          AppBackButton(
            onPressed: () => Navigator.pop(context),
            color: isDark
                ? AppColors.surfaceLight.withValues(alpha: 0.7)
                : Theme.of(context).colorScheme.onSurface,
          ),
          Expanded(
            child: Text(
              'home.pointsCalendar'.tr(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: isDark
                    ? AppColors.surfaceLight
                    : Theme.of(context).colorScheme.onSurface,
                letterSpacing: -0.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(bool isDark, Color cardBg) {
    final daysInMonth = DateUtils.getDaysInMonth(
      _viewMonth.year,
      _viewMonth.month,
    );
    final firstWeekday = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday;
    // Flutter: Mon=1 ... Sun=7; we want Sun=0
    final startOffset = firstWeekday % 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          boxShadow: [
            BoxShadow(
              color: Theme.of(
                context,
              ).colorScheme.shadow.withValues(alpha: isDark ? 0.2 : 0.05),

              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _buildMonthNav(isDark),
            const SizedBox(height: AppSpacing.md),
            _buildWeekHeader(isDark),
            const Divider(height: 16, thickness: 0.5),
            _buildDaysGrid(daysInMonth, startOffset, isDark),
          ],
        ),
      ),
    );
  }

  Widget _buildMonthNav(bool isDark) {
    final monthLabel = DateFormat('MMMM yyyy').format(_viewMonth);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _navButton(Icons.chevron_left, _prevMonth, isDark),
        Flexible(
          child: Text(
            monthLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: isDark
                  ? AppColors.surfaceLight
                  : Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        _navButton(Icons.chevron_right, _nextMonth, isDark),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap, bool isDark) {
    return TapTarget(
      onTap: onTap,
      child: Icon(
        icon,
        size: 22,
        color: isDark
            ? AppColors.surfaceLight.withValues(alpha: 0.6)
            : Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildWeekHeader(bool isDark) {
    // Sunday first, as the grid below; narrow names follow Intl.defaultLocale.
    final days = DateFormat().dateSymbols.STANDALONENARROWWEEKDAYS;
    return Row(
      children: days
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Center(
                child: Text(
                  e.value,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: e.key == 0 || e.key == 6
                        ? ProgressPalette.flameOrange
                        : isDark
                        ? AppColors.surfaceLight.withValues(alpha: 0.6)
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildDaysGrid(int daysInMonth, int startOffset, bool isDark) {
    final cells = <Widget>[];

    for (int i = 0; i < startOffset; i++) {
      cells.add(const SizedBox.shrink());
    }

    for (int day = 1; day <= daysInMonth; day++) {
      final date = DateTime(_viewMonth.year, _viewMonth.month, day);
      final checkin = _isCheckin(date);
      final today = _isToday(date);
      final future = _isFuture(date);

      cells.add(
        _DayCell(
          day: day,
          isCheckin: checkin,
          isToday: today,
          isFuture: future,
          isDark: isDark,
        ),
      );
    }

    while (cells.length < _kCalendarCellCount) {
      cells.add(const SizedBox.shrink());
    }

    return GridView.count(
      crossAxisCount: 7,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 4,
      crossAxisSpacing: 0,
      childAspectRatio: 1.0,
      children: cells,
    );
  }

  Widget _buildReminderSection(bool isDark) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
      child: Container(
        decoration: BoxDecoration(
          color: ProgressPalette.calendarSky,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'home.setupCheckinReminder'.tr(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: AppColors.surfaceLight,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _reminderRow(
              icon: Icons.notifications_outlined,
              label: 'home.checkinReminder'.tr(),
              trailing: Transform.scale(
                scale: TapTargetBox.applies(context) ? 1 : 0.9,
                child: Switch(
                  value: _reminderEnabled,
                  onChanged: (val) {
                    setState(() => _reminderEnabled = val);
                    _saveReminderPrefs();
                  },
                  activeThumbColor: AppColors.surfaceLight,
                  activeTrackColor: ProgressPalette.calendarBlue,
                  inactiveThumbColor: AppColors.surfaceLight,
                  inactiveTrackColor: AppColors.surfaceLight.withValues(
                    alpha: 0.4,
                  ),
                  materialTapTargetSize: TapTargetBox.applies(context)
                      ? MaterialTapTargetSize.padded
                      : MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            if (_reminderEnabled) ...[
              const SizedBox(height: 10),
              _reminderRow(
                icon: Icons.access_time_outlined,
                label: 'home.setTime'.tr(),
                trailing: TapTarget(
                  onTap: _pickTime,
                  child: Text(
                    _reminderTime.format(context),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: AppColors.surfaceLight,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _reminderRow({
    required IconData icon,
    required String label,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Icon(icon, color: AppColors.surfaceLight, size: 22),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.surfaceLight,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        trailing,
      ],
    );
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _reminderTime,
    );
    if (picked != null && mounted) {
      setState(() => _reminderTime = picked);
      _saveReminderPrefs();
    }
  }
}

class _DayCell extends StatelessWidget {
  final int day;
  final bool isCheckin;
  final bool isToday;
  final bool isFuture;
  final bool isDark;

  const _DayCell({
    required this.day,
    required this.isCheckin,
    required this.isToday,
    required this.isFuture,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    Color textColor;
    Color? bgColor;
    FontWeight fontWeight = FontWeight.w500;

    if (isCheckin) {
      bgColor = ProgressPalette.streakOrange;
      textColor = AppColors.surfaceLight;
      fontWeight = FontWeight.w700;
    } else if (isToday) {
      bgColor = null;
      textColor = ProgressPalette.streakOrange;
      fontWeight = FontWeight.w700;
    } else if (isFuture) {
      textColor = isDark
          ? AppColors.surfaceLight.withValues(alpha: 0.24)
          : ProgressPalette.dayOff;
    } else {
      textColor = isDark
          ? AppColors.surfaceLight.withValues(alpha: 0.7)
          : Theme.of(context).colorScheme.onSurface;
    }

    Widget cell = Center(
      child: Text(
        '$day',
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: fontWeight,
          color: textColor,
        ),
      ),
    );

    if (bgColor != null) {
      cell = Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(color: bgColor, shape: BoxShape.circle),
        child: cell,
      );
    } else if (isToday) {
      cell = Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ProgressPalette.streakOrange, width: 2),
        ),
        child: cell,
      );
    }

    return cell;
  }
}
