import 'package:easy_localization/easy_localization.dart';

/// "Just now", "5 min ago", "Yesterday", "3 d ago" in the current language.
///
/// From a week on it shows a locale date ("16 thg 11, 2026" / "Nov 16, 2026"),
/// or, with [coarse], keeps counting in weeks, months and years.
/// `Intl.defaultLocale` follows the app language (see `LocaleRefresher`).
String relativeTime(DateTime time, {DateTime? now, bool coarse = false}) {
  final diff = (now ?? DateTime.now()).difference(time);
  if (diff.inMinutes < 1) return 'datetime.justNow'.tr();
  if (diff.inHours < 1) {
    return 'datetime.minutesAgo'.tr(
      namedArgs: {'minutes': '${diff.inMinutes}'},
    );
  }
  if (diff.inDays < 1) {
    return 'datetime.hoursAgo'.tr(namedArgs: {'hours': '${diff.inHours}'});
  }
  if (diff.inDays == 1) return 'datetime.yesterday'.tr();
  if (diff.inDays < 7) {
    return 'datetime.daysAgo'.tr(namedArgs: {'days': '${diff.inDays}'});
  }
  if (!coarse) return DateFormat.yMMMd().format(time);
  if (diff.inDays < 30) {
    return 'datetime.weeksAgo'.tr(namedArgs: {'weeks': '${diff.inDays ~/ 7}'});
  }
  if (diff.inDays < 365) {
    return 'datetime.monthsAgo'.tr(
      namedArgs: {'months': '${diff.inDays ~/ 30}'},
    );
  }
  return 'datetime.yearsAgo'.tr(namedArgs: {'years': '${diff.inDays ~/ 365}'});
}

/// "3 days left" / "5 hours left".
String timeLeft(int hours) => hours >= 24
    ? 'datetime.daysLeft'.tr(namedArgs: {'count': '${hours ~/ 24}'})
    : 'datetime.hoursLeft'.tr(namedArgs: {'count': '$hours'});
