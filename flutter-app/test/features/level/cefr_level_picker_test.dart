import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/presentation/widgets/cefr_level_picker.dart';

void main() {
  testWidgets('marks the certified level and the levels above it', (
    tester,
  ) async {
    String? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: CefrLevelPicker(
              value: 'A2',
              certifiedLevel: 'B1',
              onChanged: (code) => picked = code,
            ),
          ),
        ),
      ),
    );

    expect(find.text('profile.levelCertifiedTag'), findsOneWidget);
    // B2, C1, C2 sit above the certified B1.
    expect(find.text('profile.levelUnverifiedTag'), findsNWidgets(3));

    await tester.tap(find.text('onboarding.levelC1'));
    expect(picked, 'C1');
  });

  test('the onboarding and profile lists are the same six levels', () {
    expect(cefrLevelOptions.map((o) => o.code), [
      'A1',
      'A2',
      'B1',
      'B2',
      'C1',
      'C2',
    ]);
  });
}
