import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/features/admin/features/auth/presentation/login_screen.dart';
import 'package:provider/provider.dart';

void main() {
  setUpAll(() {
    dotenv.loadFromString(isOptional: true);
  });

  Future<void> pumpLoginScreen(
    WidgetTester tester, {
    required Size viewportSize,
  }) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = viewportSize;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      ChangeNotifierProvider(
        create: (_) => AuthProvider(),
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.pump();
  }

  testWidgets('background fills a mobile viewport', (tester) async {
    const viewportSize = Size(390, 844);
    await pumpLoginScreen(tester, viewportSize: viewportSize);

    expect(
      tester.getSize(find.byKey(const Key('admin-login-background'))),
      viewportSize,
    );
  });

  testWidgets('background fills a desktop web viewport', (tester) async {
    const viewportSize = Size(1440, 900);
    await pumpLoginScreen(tester, viewportSize: viewportSize);

    expect(
      tester.getSize(find.byKey(const Key('admin-login-background'))),
      viewportSize,
    );
  });
}
