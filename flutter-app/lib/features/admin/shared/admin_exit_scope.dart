import 'package:flutter/widgets.dart';

class AdminExitScope extends InheritedWidget {
  const AdminExitScope({super.key, required this.onExit, required super.child});

  final VoidCallback onExit;

  static AdminExitScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<AdminExitScope>();
  }

  @override
  bool updateShouldNotify(AdminExitScope oldWidget) {
    return onExit != oldWidget.onExit;
  }
}
