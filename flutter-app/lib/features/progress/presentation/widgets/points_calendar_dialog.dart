import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/core/services/notification_service.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../../domain/entities/streak_entity.dart';

const _kReminderEnabledKey = 'checkin_reminder_enabled';
const _kReminderHourKey = 'checkin_reminder_hour';
const _kReminderMinuteKey = 'checkin_reminder_minute';
const _kCalendarCellCount = 42;

void showPointsCalendarDialog(BuildContext context, StreakEntity streak) {
  showDialog(
    context: context,
    barrierColor: Colors.black54,
    builder: (ctx) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: _PointsCalendarContent(streak: streak),
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
    setState(() {
      _reminderEnabled = prefs.getBool(_kReminderEnabledKey) ?? false;
      final hour = prefs.getInt(_kReminderHourKey) ?? 12;
      final minute = prefs.getInt(_kReminderMinuteKey) ?? 0;
      _reminderTime = TimeOfDay(hour: hour, minute: minute);
    });
  }

  Future<void> _saveReminderPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kReminderEnabledKey, _reminderEnabled);
    await prefs.setInt(_kReminderHourKey, _reminderTime.hour);
    await prefs.setInt(_kReminderMinuteKey, _reminderTime.minute);

    final notificationService = sl<NotificationService>();
    await notificationService.ensureInitialized();
    if (_reminderEnabled) {
      await notificationService.scheduleDailyReminder(_reminderTime);
    } else {
      await notificationService.cancelDailyReminder();
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
    return day.year == now.year &&
        day.month == now.month &&
        day.day == now.day;
  }

  bool _isFuture(DateTime day) {
    final now = DateTime.now();
    return day.isAfter(DateTime(now.year, now.month, now.day));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? AppColors.surfaceDark : const Color(0xFFFAF6F2);
    final cardBg = isDark ? AppColors.surfaceDarkElevated : Colors.white;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: Container(
        color: bg,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(context, isDark),
            _buildCalendar(isDark, cardBg),
            const SizedBox(height: 12),
            _buildReminderSection(isDark),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 16, 16, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.pop(context),
            icon: Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 20,
              color: isDark ? Colors.white70 : AppColors.textDark,
            ),
          ),
          Text(
            'home.pointsCalendar'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: isDark ? Colors.white : AppColors.textDark,
              letterSpacing: -0.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCalendar(bool isDark, Color cardBg) {
    final daysInMonth =
        DateUtils.getDaysInMonth(_viewMonth.year, _viewMonth.month);
    final firstWeekday = DateTime(_viewMonth.year, _viewMonth.month, 1).weekday;
    // Flutter: Mon=1 ... Sun=7; we want Sun=0
    final startOffset = firstWeekday % 7;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cardBg,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          children: [
            _buildMonthNav(isDark),
            const SizedBox(height: 12),
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
        Text(
          monthLabel,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        _navButton(Icons.chevron_right, _nextMonth, isDark),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap, bool isDark) {
    return GestureDetector(
      onTap: onTap,
      child: Icon(
        icon,
        size: 22,
        color: isDark ? Colors.white60 : AppColors.textGrey,
      ),
    );
  }

  Widget _buildWeekHeader(bool isDark) {
    const days = ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    return Row(
      children: days
          .asMap()
          .entries
          .map(
            (e) => Expanded(
              child: Center(
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: e.key == 0 || e.key == 6
                        ? const Color(0xFFFF8C00)
                        : isDark
                        ? Colors.white60
                        : AppColors.textGrey,
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

      cells.add(_DayCell(
        day: day,
        isCheckin: checkin,
        isToday: today,
        isFuture: future,
        isDark: isDark,
      ));
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
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF4BAFF0),
          borderRadius: BorderRadius.circular(18),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'home.setupCheckinReminder'.tr(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            _reminderRow(
              icon: Icons.notifications_outlined,
              label: 'home.checkinReminder'.tr(),
              trailing: Transform.scale(
                scale: 0.9,
                child: Switch(
                  value: _reminderEnabled,
                  onChanged: (val) {
                    setState(() => _reminderEnabled = val);
                    _saveReminderPrefs();
                  },
                  activeThumbColor: Colors.white,
                  activeTrackColor: const Color(0xFF2575CC),
                  inactiveThumbColor: Colors.white,
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ),
            if (_reminderEnabled) ...[
              const SizedBox(height: 10),
              _reminderRow(
                icon: Icons.access_time_outlined,
                label: 'home.setTime'.tr(),
                trailing: GestureDetector(
                  onTap: _pickTime,
                  child: Text(
                    _reminderTime.format(context),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
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
        Icon(icon, color: Colors.white, size: 22),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
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
    if (picked != null) {
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
      bgColor = const Color(0xFFFF8C35);
      textColor = Colors.white;
      fontWeight = FontWeight.w700;
    } else if (isToday) {
      bgColor = null;
      textColor = const Color(0xFFFF8C35);
      fontWeight = FontWeight.w700;
    } else if (isFuture) {
      textColor = isDark
          ? Colors.white24
          : const Color(0xFFB0B0B0);
    } else {
      textColor = isDark ? Colors.white70 : AppColors.textDark;
    }

    Widget cell = Center(
      child: Text(
        '$day',
        style: TextStyle(
          fontSize: 14,
          fontWeight: fontWeight,
          color: textColor,
        ),
      ),
    );

    if (bgColor != null) {
      cell = Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: bgColor,
          shape: BoxShape.circle,
        ),
        child: cell,
      );
    } else if (isToday) {
      cell = Container(
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: const Color(0xFFFF8C35), width: 2),
        ),
        child: cell,
      );
    }

    return cell;
  }
}
