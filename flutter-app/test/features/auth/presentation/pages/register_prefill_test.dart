import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/presentation/pages/register_page.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:mockito/mockito.dart';
import 'package:provider/provider.dart';

class _Auth extends Mock with ChangeNotifier implements AuthProvider {
  @override
  bool get isLoading => false;

  @override
  String? get errorMessage => null;

  @override
  bool get isAuthenticated => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => EasyLocalization.logger.enableLevels = []);

  Future<String?> nameFieldText(WidgetTester tester, String? name) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: _Auth(),
        child: MaterialApp(home: RegisterPage(initialName: name)),
      ),
    );
    final first = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    return first.controller?.text;
  }

  testWidgets('the name asked before sign-up is already in the form', (
    tester,
  ) async {
    expect(await nameFieldText(tester, 'Linh'), 'Linh');
  });

  testWidgets('without an earlier answer the name field starts empty', (
    tester,
  ) async {
    expect(await nameFieldText(tester, null), '');
  });
}
