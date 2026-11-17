import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/entitlement_service.dart';
import 'package:lexilingo_app/core/widgets/premium_gate.dart';

class _Free extends Fake implements EntitlementService {
  @override
  Future<bool> fetchCached({String entitlementId = 'premium'}) async => false;
}

void main() {
  setUp(() => sl.registerSingleton<EntitlementService>(_Free()));
  tearDown(() => sl.reset());

  testWidgets('the locked scrim takes the shape of the wrapped button', (
    tester,
  ) async {
    final radius = BorderRadius.circular(26);
    await tester.pumpWidget(
      MaterialApp(
        home: PremiumGate(
          borderRadius: radius,
          child: const SizedBox(width: 200, height: 52),
        ),
      ),
    );
    await tester.pump();

    expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      radius,
    );
  });
}
