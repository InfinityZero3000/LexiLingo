import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/navigation/token_routes.dart';

void main() {
  testWidgets('a route name with a query reaches its page with the token', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    final routes = <String, WidgetBuilder>{
      '/verify-email': (context) {
        final args = ModalRoute.of(context)!.settings.arguments as Map;
        return Text('token=${args['token']}');
      },
    };
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Text('home'),
        routes: routes,
        onGenerateRoute: (settings) => queryRoute(settings, routes),
      ),
    );

    navigator.currentState!.pushNamed('/verify-email?token=abc.def');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('token=abc.def'), findsOneWidget);
  });

  test('names without a query, or unknown paths, are left to the app', () {
    final routes = <String, WidgetBuilder>{'/x': (_) => const SizedBox()};
    expect(queryRoute(const RouteSettings(name: '/x'), routes), isNull);
    expect(queryRoute(const RouteSettings(name: '/y?token=1'), routes), isNull);
  });
}
