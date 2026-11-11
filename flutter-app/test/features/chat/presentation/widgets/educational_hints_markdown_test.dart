import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/chat/domain/entities/educational_hints.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/educational_hints_widgets.dart';

void main() {
  testWidgets('grammar explanation renders **bold** instead of asterisks', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: GrammarCorrectionBadge(
            correction: GrammarCorrection(
              original: 'I have studied in 2020',
              corrected: 'I studied in 2020',
              explanation: 'Use the **Past Simple** for finished actions.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Past Simple', findRichText: true), findsOneWidget);
    expect(find.textContaining('**', findRichText: true), findsNothing);
  });
}
