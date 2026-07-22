import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/navigation/learner_route.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';

void main() {
  testWidgets('builder scopes tactile theme to learner content', (
    tester,
  ) async {
    AppTactileTheme? extension;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: LearnerRoute.builder((context) {
            extension = Theme.of(context).extension<AppTactileTheme>();
            return const Text('learner');
          }),
        ),
      ),
    );

    expect(find.text('learner'), findsOneWidget);
    expect(extension, isNotNull);
  });

  testWidgets('push preserves settings and generic result', (tester) async {
    String? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await LearnerRoute.push<String>(
                context,
                (context) => Builder(
                  builder: (context) => TextButton(
                    onPressed: () => Navigator.pop(context, 'done'),
                    child: Text(
                      '${ModalRoute.settingsOf(context)?.name}:'
                      '${Theme.of(context).extension<AppTactileTheme>() != null}',
                    ),
                  ),
                ),
                settings: const RouteSettings(name: '/probe'),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('/probe:true'), findsOneWidget);
    await tester.tap(find.text('/probe:true'));
    await tester.pumpAndSettle();
    expect(result, 'done');
  });

  testWidgets('pushReplacement preserves settings and fullscreen mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => LearnerRoute.pushReplacement<void, void>(
              context,
              (context) => Text(
                '${ModalRoute.settingsOf(context)?.name}:'
                '${ModalRoute.of(context)?.fullscreenDialog}:'
                '${Theme.of(context).extension<AppTactileTheme>() != null}',
              ),
              settings: const RouteSettings(name: '/replacement'),
              fullscreenDialog: true,
            ),
            child: const Text('replace'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('replace'));
    await tester.pumpAndSettle();

    expect(find.text('replace'), findsNothing);
    expect(find.text('/replacement:true:true'), findsOneWidget);
  });

  testWidgets(
    'pre-auth and admin content keep the global theme in both modes',
    (tester) async {
      for (final brightness in Brightness.values) {
        ThemeData? observed;
        final global = ThemeData(brightness: brightness);
        await tester.pumpWidget(
          MaterialApp(
            theme: global,
            darkTheme: global,
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
            home: Builder(
              builder: (context) {
                observed = Theme.of(context);
                return const SizedBox();
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(observed!.extension<AppTactileTheme>(), isNull);
        expect(observed!.brightness, brightness);
        expect(observed!.cardTheme, global.cardTheme);
        expect(observed!.filledButtonTheme, global.filledButtonTheme);
      }
    },
  );
}
