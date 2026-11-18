import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/admin/shared/widgets/open_in_web_admin_tile.dart';

void main() {
  testWidgets('opens the web admin at the given path', (tester) async {
    Uri? opened;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: OpenInWebAdminTile(
            body: 'Do it on the web',
            path: '/admin/users',
            launch: (uri) async {
              opened = uri;
              return true;
            },
          ),
        ),
      ),
    );
    expect(find.text('Do it on the web'), findsOneWidget);
    await tester.tap(find.text('admin.webOnly.open'));
    await tester.pump();
    expect(opened.toString(), '$adminWebUrl/admin/users');
    final button = find.ancestor(
      of: find.text('admin.webOnly.open'),
      matching: find.byWidgetPredicate((w) => w is TextButton),
    );
    expect(tester.getSize(button).height, greaterThanOrEqualTo(44));
  });
}
