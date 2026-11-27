import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'admin_shell.dart';
import 'admin_theme_toggle.dart';

/// The frame of one admin screen: a menu button that opens the shell's drawer
/// on phones (the sidebar is always there on wide layouts), a title and the
/// screen's own actions.
class AdminPage extends StatelessWidget {
  const AdminPage({
    super.key,
    required this.title,
    required this.body,
    this.actions = const [],
    this.floatingActionButton,
    this.bottom,
    this.showMenu = true,
  });

  final String title;
  final Widget body;
  final List<Widget> actions;
  final Widget? floatingActionButton;
  final PreferredSizeWidget? bottom;

  /// False for a screen pushed above the shell, which gets a back button.
  final bool showMenu;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= adminWideBreakpoint;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !showMenu,
        leading: showMenu && !wide
            ? IconButton(
                constraints: const BoxConstraints(
                  minWidth: kMinTapTarget,
                  minHeight: kMinTapTarget,
                ),
                icon: const Icon(Icons.menu_rounded),
                onPressed: AdminShell.openDrawer,
              )
            : null,
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [...actions, const AdminThemeToggleButton()],
        bottom: bottom,
      ),
      floatingActionButton: floatingActionButton,
      body: body,
    );
  }
}
