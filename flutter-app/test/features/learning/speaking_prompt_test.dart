import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/learning/domain/entities/lesson_entity.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/exercises/exercise_chrome.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/lesson_speaking_recorder.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/premium_exercise_widgets.dart';
import 'package:lexilingo_app/features/voice/presentation/providers/tts_settings_provider.dart';
import 'package:provider/provider.dart';

const _sentence = 'Could you tell me where gate twelve is';
final _exercise = Exercise(
  id: 'speak',
  type: ExerciseType.translate,
  uiType: 'speaking_repeat',
  question: "Repeat: '$_sentence?'",
  correctAnswer: _sentence,
);

void main() {
  for (final widget in <Widget>[
    SpeakingRepeatWidget(
      exercise: _exercise,
      onAnswer: (_) {},
      isAnswered: false,
    ),
    PronunciationPracticeWidget(
      exercise: _exercise,
      onAnswer: (_) {},
      isAnswered: false,
    ),
  ]) {
    testWidgets('${widget.runtimeType} shows and reads only the sentence', (
      tester,
    ) async {
      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => TtsSettingsProvider(),
          child: MaterialApp(home: Scaffold(body: widget)),
        ),
      );

      expect(find.text('"$_sentence"'), findsOneWidget);
      expect(find.textContaining('Repeat:'), findsNothing);
      expect(
        tester.widget<CircleAudioButton>(find.byType(CircleAudioButton)).text,
        _sentence,
      );
    });
  }

  testWidgets('a refused microphone is not reported as a failed match', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LessonSpeakingRecorder(
            targetText: _sentence,
            isAnswered: false,
            onApproved: (_) {},
            startRecording: () async => throw StateError('no permission'),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('lesson-speaking-mic')));
    await tester.pumpAndSettle();

    expect(find.text('voice.notMatchedTryAgain'), findsNothing);
    expect(find.text('voice.micPermissionRetry'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });
}
