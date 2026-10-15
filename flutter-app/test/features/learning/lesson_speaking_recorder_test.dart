import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';

void main() {
  Widget buildRecorder({
    required Future<String> Function(Uint8List) transcribe,
    required ValueChanged<String> onApproved,
    ValueChanged<String>? onAttempt,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: LessonSpeakingRecorder(
          targetText: 'Could you please speak more slowly?',
          isAnswered: false,
          onApproved: onApproved,
          onAttempt: onAttempt,
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


  testWidgets('a rejected take still reports what the learner managed', (
    tester,
  ) async {
    final attempts = <String>[];
    String? approvedAnswer;

    await tester.pumpWidget(
      buildRecorder(
        transcribe: (_) async => 'could you speak slowly',
        onApproved: (answer) => approvedAnswer = answer,
        onAttempt: attempts.add,
      ),
    );

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pumpAndSettle();

    // Nothing was approved, but the attempt is no longer thrown away: the
    // pipeline used to see successes only, so speaking accuracy was 100% by
    // construction.
    expect(approvedAnswer, isNull);
    expect(attempts, ['could you speak slowly']);
  });

  testWidgets('retrying reports the best take, not the latest', (tester) async {
    final attempts = <String>[];
    // Measured against SpeakingAnswerMatcher: 0.265, 0.647, 0.147 — all below
    // the 0.85 pass mark, so the learner never gets approved.
    final transcripts = <String>[
      'could you',
      'could you please speak',
      'speak',
    ];
    var index = 0;

    await tester.pumpWidget(
      buildRecorder(
        transcribe: (_) async => transcripts[index++],
        onApproved: (_) {},
        onAttempt: attempts.add,
      ),
    );

    for (var i = 0; i < transcripts.length; i++) {
      await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50)); // let _start settle
      await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
      await tester.pumpAndSettle();
    }

    expect(attempts.length, 3);
    // The third take was worse; the best one stands.
    expect(attempts.last, 'could you please speak');
  });
}
