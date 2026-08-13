import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';

void main() {
  Widget buildRecorder({
    required Future<String> Function(Uint8List) transcribe,
    required ValueChanged<String> onApproved,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LessonSpeakingRecorder(
          targetText: 'Could you please speak more slowly?',
          isAnswered: false,
          onApproved: onApproved,
          startRecording: () async {},
          stopRecording: () async => Uint8List.fromList([1, 2, 3]),
          transcribeAudio: transcribe,
        ),
      ),
    );
  }

  testWidgets('starts recording and approves a matching transcript', (
    tester,
  ) async {
    String? approvedAnswer;

    await tester.pumpWidget(
      buildRecorder(
        transcribe: (_) async => 'Could you please speak more slowly',
        onApproved: (answer) => approvedAnswer = answer,
      ),
    );

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pump();
    expect(find.text('voice.recordingTapToStop'), findsOneWidget);

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pumpAndSettle();

    expect(approvedAnswer, 'Could you please speak more slowly');
    expect(find.text('voice.saidCorrectly'), findsOneWidget);
  });

  testWidgets('keeps the exercise retryable when transcript does not match', (
    tester,
  ) async {
    String? approvedAnswer;

    await tester.pumpWidget(
      buildRecorder(
        transcribe: (_) async => 'What time does the train leave',
        onApproved: (answer) => approvedAnswer = answer,
      ),
    );

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pumpAndSettle();

    expect(approvedAnswer, isNull);
    expect(find.text('voice.notMatchedTryAgain'), findsOneWidget);
    expect(
      find.textContaining('What time does the train leave'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pump();
    expect(find.text('voice.recordingTapToStop'), findsOneWidget);
  });
}
