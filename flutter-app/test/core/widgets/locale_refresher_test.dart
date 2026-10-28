import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/locale_refresher.dart';

String _table = 'en';

class _Delegate extends LocalizationsDelegate<String> {
  const _Delegate();
  @override
  bool isSupported(Locale locale) => true;
  @override
  Future<String> load(Locale locale) async {
    await Future<void>.delayed(const Duration(milliseconds: 10));
    _table = locale.languageCode;
    return _table;
  }

  @override
  bool shouldReload(_Delegate old) => false;
}

/// Reads a static table like `.tr()` does and subscribes to nothing.
class _Probe extends StatefulWidget {
  const _Probe();
  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  Widget build(BuildContext context) =>
      Text(_table, textDirection: TextDirection.ltr);
}

Widget _app(Locale locale, {required bool refresh}) => MaterialApp(
  locale: locale,
  supportedLocales: const [Locale('en'), Locale('fr')],
  localizationsDelegates: const [
    _Delegate(),
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  builder: (context, child) =>
      refresh ? LocaleRefresher(child: child!) : child!,
  home: const _Probe(),
);

void main() {
  for (final refresh in [false, true]) {
    testWidgets('locale switch reaches a const screen: refresher=$refresh', (
      tester,
    ) async {
      _table = 'en';
      await tester.pumpWidget(_app(const Locale('en'), refresh: refresh));
      await tester.pumpAndSettle();
      expect(find.text('en'), findsOneWidget);

      await tester.pumpWidget(_app(const Locale('fr'), refresh: refresh));
      await tester.pumpAndSettle();
      expect(find.text(refresh ? 'fr' : 'en'), findsOneWidget);
    });
  }
}
