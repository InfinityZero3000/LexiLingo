import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/course/presentation/utils/course_labels.dart';

Color getLevelColor(String level, {bool isDark = false}) =>
    courseLevelColor(level, isDark: isDark);

String localizedCourseLevel(String level) => courseLevelLabel(level);
