import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';

typedef LearnerWidgetBuilder = Widget Function(BuildContext context);

abstract final class LearnerRoute {
  static WidgetBuilder builder(LearnerWidgetBuilder child) =>
      (context) => LearnerTheme(child: Builder(builder: child));

  static Future<T?> push<T>(
    BuildContext context,
    LearnerWidgetBuilder child, {
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) => Navigator.of(context).push<T>(
    MaterialPageRoute<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => LearnerTheme(child: Builder(builder: child)),
    ),
  );

  static Future<T?> pushReplacement<T, TO>(
    BuildContext context,
    LearnerWidgetBuilder child, {
    TO? result,
    RouteSettings? settings,
    bool fullscreenDialog = false,
  }) => Navigator.of(context).pushReplacement<T, TO>(
    MaterialPageRoute<T>(
      settings: settings,
      fullscreenDialog: fullscreenDialog,
      builder: (context) => LearnerTheme(child: Builder(builder: child)),
    ),
    result: result,
  );
}
