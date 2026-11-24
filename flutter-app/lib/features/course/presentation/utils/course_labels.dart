import 'package:easy_localization/easy_localization.dart';

export 'course_tag_label.dart';

String courseLevelLabel(String level) {
  final key = level.trim().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
  const keys = {
    'beginner': 'beginner',
    'elementary': 'elementary',
    'preintermediate': 'preIntermediate',
    'intermediate': 'intermediate',
    'upperintermediate': 'upperIntermediate',
    'advanced': 'advanced',
  };
  final name = keys[key];
  return name == null ? level : 'course.difficulty.$name'.tr();
}

String courseLanguageLabel(String language) {
  switch (language.trim().toLowerCase()) {
    case 'en':
    case 'en-us':
    case 'en_us':
    case 'english':
      return 'course.langEnglish'.tr();
    case 'es':
    case 'spanish':
      return 'course.langSpanish'.tr();
    case 'vi':
    case 'vn':
    case 'vietnamese':
      return 'course.langVietnamese'.tr();
    default:
      return language;
  }
}
