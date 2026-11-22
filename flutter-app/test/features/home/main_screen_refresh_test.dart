import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/home/presentation/pages/main_screen.dart';

void main() {
  final now = DateTime(2026, 11, 20, 9);

  test('signed out, popping back refreshes nothing', () {
    expect(
      progressRefreshDue(authenticated: false, last: null, now: now),
      isFalse,
    );
  });

  test('signed in, the first refresh goes out', () {
    expect(
      progressRefreshDue(authenticated: true, last: null, now: now),
      isTrue,
    );
  });

  test('two refreshes within two seconds collapse into one', () {
    final last = now.subtract(const Duration(seconds: 1));
    expect(
      progressRefreshDue(authenticated: true, last: last, now: now),
      isFalse,
    );
    final older = now.subtract(const Duration(seconds: 2));
    expect(
      progressRefreshDue(authenticated: true, last: older, now: now),
      isTrue,
    );
  });
}
