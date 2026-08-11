import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';

void main() {
  tearDown(LocaleService.debugReset);

  test('serializes application and coalesces pending locales', () async {
    final japanese = Completer<void>();
    final started = <String>[];
    final persisted = <String>[];
    LocaleService.debugConfigure(
      apply: (code) {
        started.add(code);
        return code == 'ja' ? japanese.future : Future.value();
      },
      persist: (code) async => persisted.add(code),
    );

    final first = LocaleService.debugRequestLocale('ja');
    final second = LocaleService.debugRequestLocale('ko');
    final third = LocaleService.debugRequestLocale('en');

    expect(started, ['ja']);
    expect(await second, isFalse);
    japanese.complete();
    expect(await first, isFalse);
    expect(await third, isTrue);
    expect(started, ['ja', 'en']);
    expect(persisted, ['en']);
  });

  test('continues draining after a started locale fails', () async {
    final japanese = Completer<void>();
    final started = <String>[];
    final persisted = <String>[];
    LocaleService.debugConfigure(
      apply: (code) {
        started.add(code);
        return code == 'ja' ? japanese.future : Future.value();
      },
      persist: (code) async => persisted.add(code),
    );

    final first = LocaleService.debugRequestLocale('ja');
    final second = LocaleService.debugRequestLocale('en');
    japanese.completeError(StateError('font load failed'));

    await expectLater(first, throwsStateError);
    expect(await second, isTrue);
    expect(started, ['ja', 'en']);
    expect(persisted, ['en']);
  });
}
