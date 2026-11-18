import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'admin_shell.dart';

/// Widest a screen's content grows; beyond it the content stays centred so a
/// list does not stretch across a desktop-sized window.
const adminContentMaxWidth = 880.0;

/// App bar and width limit shared by admin screens. A top-level screen gets
/// the drawer button on phones (the sidebar is always there when wide); a
/// pushed screen ([pushed]) gets a back button.
class AdminScreenScaffold extends StatelessWidget {
  const AdminScreenScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.pushed = false,
    this.floatingActionButton,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final bool pushed;
  final Widget? floatingActionButton;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= adminWideBreakpoint;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: pushed
            ? const AppBackButton()
            : (wide
                  ? null
                  : IconButton(
                      onPressed: AdminShell.openDrawer,
                      icon: const Icon(Icons.menu_rounded),
                    )),
        title: Text(title),
        actions: actions,
      ),
      floatingActionButton: floatingActionButton,
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: adminContentMaxWidth),
          child: body,
        ),
      ),
    );
  }
}
