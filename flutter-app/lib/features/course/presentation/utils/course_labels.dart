import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_category_entity.dart';

export 'course_tag_label.dart';

/// Maps any raw level string (CEFR code or English difficulty name) to its
/// canonical CEFR code when known (`A1`..`C2`), or returns the trimmed input.
String courseCefrCode(String level) {
  final key = level.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (key) {
    'a1' || 'beginner' => 'A1',
    'a2' || 'elementary' => 'A2',
    'b1' || 'preintermediate' || 'intermediate' => 'B1',
    'b2' || 'upperintermediate' => 'B2',
    'c1' || 'advanced' => 'C1',
    'c2' || 'expert' || 'proficient' => 'C2',
    _ => level.trim().toUpperCase(),
  };
}

/// Maps any raw level string (CEFR code or English difficulty name) to its
/// localized difficulty label (e.g. "Người mới", "Trung cấp").
String courseLevelLabel(String level) {
  final key = level.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  const keys = {
    'a1': 'beginner',
    'beginner': 'beginner',
    'a2': 'elementary',
    'elementary': 'elementary',
    'b1': 'intermediate',
    'preintermediate': 'preIntermediate',
    'intermediate': 'intermediate',
    'b2': 'upperIntermediate',
    'upperintermediate': 'upperIntermediate',
    'c1': 'advanced',
    'c2': 'advanced',
    'advanced': 'advanced',
  };
  final name = keys[key];
  return name == null ? level : 'course.difficulty.$name'.tr();
}

/// Composite badge label combining CEFR code and localized difficulty name
/// (e.g. "A1 · Người mới", "B1 · Trung cấp") for instant recognition on cards.
String courseLevelBadgeLabel(String level) {
  final code = courseCefrCode(level);
  final label = courseLevelLabel(level);
  if (code.toLowerCase() == label.toLowerCase() || label.isEmpty) {
    return code;
  }
  return '$code · $label';
}

/// Consistent level badge color across all course screens, supporting both
/// CEFR codes (`A1`–`C2`) and difficulty names (`Beginner`–`Advanced`).
Color courseLevelColor(String level, {bool isDark = false}) {
  final key = level.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (key) {
    'a1' || 'beginner' => AppColors.cefrA,
    'a2' || 'elementary' => AppColors.teal,
    'b1' || 'preintermediate' || 'intermediate' => AppColors.orange,
    'b2' || 'upperintermediate' => AppColors.deepOrange,
    'c1' || 'advanced' => AppColors.cefrC,
    'c2' || 'expert' => AppColors.errorBright,
    _ => AppColorRoles.primary(isDark),
  };
}

/// Numeric ordering for sorting courses by difficulty level.
int courseLevelOrder(String level) {
  final key = level.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return switch (key) {
    'a1' || 'beginner' => 0,
    'a2' || 'elementary' => 1,
    'preintermediate' => 2,
    'b1' || 'intermediate' => 3,
    'b2' || 'upperintermediate' => 4,
    'c1' || 'advanced' => 5,
    'c2' || 'expert' => 6,
    _ => 7,
  };
}

/// Localized category display title using `course.tag.*` translations when the
/// category slug or name matches a standard learning domain.
String courseCategoryTitle(CourseCategoryEntity category) {
  return courseCategoryLabelFromSlug(
    category.slug,
    fallbackName: category.name,
  );
}

String courseCategoryLabelFromSlug(String slugOrName, {String? fallbackName}) {
  final normalized = slugOrName
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  final tagKey = switch (normalized) {
    'grammar' => 'grammar',
    'vocabulary' || 'vocab' => 'vocabulary',
    'conversation' => 'conversation',
    'speaking' => 'speaking',
    'listening' => 'listening',
    'reading' => 'reading',
    'writing' => 'writing',
    'pronunciation' => 'pronunciation',
    'business' || 'business-english' => 'business',
    'travel' || 'travel-english' => 'travel',
    'exam' ||
    'ielts' ||
    'toeic' ||
    'toefl' ||
    'test-prep' ||
    'test-preparation' =>
      'exam',
    _ => null,
  };
  if (tagKey != null) {
    final key = 'course.tag.$tagKey';
    final translated = key.tr();
    if (translated != key) return translated;
  }
  return (fallbackName != null && fallbackName.trim().isNotEmpty)
      ? fallbackName
      : slugOrName;
}

/// Distinct icon per category, resolving explicit icon names, emojis, or
/// falling back to the category slug so shelves never collapse to identical icons.
IconData courseCategoryIcon({String? iconName, String? slugOrName}) {
  final rawIcon = (iconName ?? '').trim().toLowerCase();
  switch (rawIcon) {
    case 'school':
    case '🎓':
      return Icons.school_rounded;
    case 'menu_book':
    case '📚':
    case '📖':
      return Icons.menu_book_rounded;
    case 'psychology':
    case '🧠':
      return Icons.psychology_rounded;
    case 'work':
    case '💼':
      return Icons.business_center_rounded;
    case 'chat':
    case '💬':
    case '🗣️':
      return Icons.forum_rounded;
    case 'flight':
    case '✈️':
    case '🌍':
      return Icons.flight_takeoff_rounded;
    case 'mic':
    case '🎙️':
      return Icons.record_voice_over_rounded;
    case 'headphones':
    case '🎧':
      return Icons.headphones_rounded;
    case 'edit':
    case '✍️':
      return Icons.edit_note_rounded;
    case 'star':
    case '⭐':
      return Icons.workspace_premium_rounded;
    case 'category':
      return Icons.category_rounded;
  }

  final slug = (slugOrName ?? rawIcon)
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return switch (slug) {
    'grammar' => Icons.auto_stories_rounded,
    'vocabulary' || 'vocab' => Icons.extension_rounded,
    'conversation' => Icons.forum_rounded,
    'speaking' => Icons.record_voice_over_rounded,
    'pronunciation' => Icons.graphic_eq_rounded,
    'listening' => Icons.headphones_rounded,
    'reading' => Icons.menu_book_rounded,
    'writing' => Icons.edit_note_rounded,
    'business' || 'business-english' => Icons.business_center_rounded,
    'travel' || 'travel-english' => Icons.flight_takeoff_rounded,
    'exam' ||
    'ielts' ||
    'toeic' ||
    'toefl' ||
    'test-prep' ||
    'test-preparation' =>
      Icons.workspace_premium_rounded,
    'cultural-english' || 'culture' => Icons.public_rounded,
    _ => Icons.menu_book_rounded,
  };
}

/// Distinct semantic color per category, honoring valid hex colors from backend
/// and falling back to a domain-specific palette by slug.
Color courseCategoryColor({
  String? colorHex,
  String? slugOrName,
  required bool isDark,
}) {
  if (colorHex != null && colorHex.trim().isNotEmpty) {
    try {
      final hex = colorHex.trim().replaceAll('#', '');
      if (hex.length == 6 || hex.length == 8) {
        return Color(int.parse(hex.length == 6 ? 'FF$hex' : hex, radix: 16));
      }
    } catch (_) {
      // Fall through to slug-based color
    }
  }
  final slug = (slugOrName ?? '')
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return switch (slug) {
    'grammar' => AppColors.cefrA,
    'vocabulary' || 'vocab' => AppColorRoles.primary(isDark),
    'conversation' || 'speaking' => AppColors.orange,
    'business' || 'business-english' => AppColors.teal,
    'travel' || 'travel-english' => AppColors.skyBlue,
    'pronunciation' || 'listening' => AppColors.pink,
    'exam' ||
    'ielts' ||
    'toeic' ||
    'toefl' ||
    'test-prep' ||
    'test-preparation' =>
      AppColors.cefrC,
    'writing' => AppColors.deepOrange,
    'reading' => AppColors.purple,
    _ => AppColorRoles.primary(isDark),
  };
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
