import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/navigation/reload_on_return.dart';
import 'package:lexilingo_app/core/services/app_navigation_service.dart';

class _Course extends StatefulWidget {
  const _Course(this.onReload);
  final VoidCallback onReload;

  @override
  State<_Course> createState() => _CourseState();
}

class _CourseState extends State<_Course> with ReloadOnReturn {
  @override
  void reload() => widget.onReload();

  @override
  Widget build(BuildContext context) => const Text('course');
}

void main() {
  testWidgets('reloads after "next lesson" replaced the first session', (
    tester,
  ) async {
    var reloads = 0;
    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [AppNavigationService.routeObserver],
        home: Scaffold(body: _Course(() => reloads++)),
      ),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    Route<void> lesson(String name) =>
        MaterialPageRoute<void>(builder: (_) => Text(name));

    navigator.push(lesson('one'));
    await tester.pumpAndSettle();
    navigator.pushReplacement(lesson('two'));
    await tester.pumpAndSettle();
    expect(reloads, 0, reason: 'the course is still covered');

    navigator.pop();
    await tester.pumpAndSettle();
    expect(reloads, 1);
  });
}
