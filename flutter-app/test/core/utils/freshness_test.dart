import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/utils/freshness.dart';

void main() {
  test('fresh only inside maxAge, never without a maxAge or a mark', () {
    var now = DateTime(2026, 11, 19, 12);
    final f = Freshness(clock: () => now);

    expect(f.isFresh(kPassiveReloadWindow), isFalse);
    f.mark();
    expect(f.isFresh(null), isFalse);
    expect(f.isFresh(kPassiveReloadWindow), isTrue);

    now = now.add(const Duration(seconds: 31));
    expect(f.isFresh(kPassiveReloadWindow), isFalse);
  });

  test('invalidate forgets the mark', () {
    final f = Freshness()..mark();
    f.invalidate();
    expect(f.isFresh(kPassiveReloadWindow), isFalse);
  });
}
