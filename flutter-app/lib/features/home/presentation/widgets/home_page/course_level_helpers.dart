import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

Color getLevelColor(String level, {bool isDark = false}) {
  switch (level.toLowerCase()) {
    case 'beginner':
      return AppColors.greenSuccessBright;
    case 'elementary':
      return AppColors.greenSuccessSoft;
    case 'intermediate':
      return AppColors.orange;
    case 'upper-intermediate':
      return AppColors.orange;
    case 'advanced':
      return AppColors.dangerGradient[0];
    default:
      return AppColorRoles.primary(isDark);
  }
}

String localizedCourseLevel(String level) {
  switch (level.toLowerCase()) {
    case 'beginner':
      return 'course.difficulty.beginner'.tr();
    case 'elementary':
      return 'course.difficulty.elementary'.tr();
    case 'intermediate':
      return 'course.difficulty.intermediate'.tr();
    case 'upper-intermediate':
      return 'course.difficulty.upperIntermediate'.tr();
    case 'advanced':
      return 'course.difficulty.advanced'.tr();
    default:
      return level;
  }
}
