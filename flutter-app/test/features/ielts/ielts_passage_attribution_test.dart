import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/pages/ielts_sitting_page.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';
import 'package:lexilingo_app/features/ielts/presentation/widgets/ielts_passage_attribution.dart';

class _Stub extends IeltsDataSource {
  _Stub(this.part) : super(apiClient: ApiClient());
  final IeltsPart part;

  @override
  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async => IeltsAttemptState(
    attemptId: 'a',
    status: 'in_progress',
    skillScope: 'reading',
    paper: IeltsPaper(
      sections: [
        IeltsSection(skill: IeltsSkill.reading, parts: [part]),
      ],
    ),
  );
}

const _test = IeltsTestSummary(
  id: 't',
  title: 'Reading',
  testType: 'academic',
  skillScope: 'reading',
);

IeltsPart withFieldsPart() => IeltsPart.fromJson({
  'order': 1,
  'passage_title': 'Bees',
  'passage_text': 'Bees are insects.',
  'attribution': "From Wikipedia article 'Bee' (rev 1), CC BY-SA 4.0",
  'license_id': 'CC-BY-SA-4.0',
  'license_url': 'https://creativecommons.org/licenses/by-sa/4.0/',
  'source_url': 'https://en.wikipedia.org/wiki/Bee',
  'adapted': true,
});

Future<void> _sit(WidgetTester tester, IeltsPart part) async {
  sl.registerFactory<IeltsProvider>(
    () => IeltsProvider(dataSource: _Stub(part)),
  );
  await tester.pumpWidget(
    const MaterialApp(home: IeltsSittingPage(test: _test)),
  );
  await tester.pumpAndSettle();
}

void main() {
  tearDown(() => sl.reset());

  testWidgets('reading screen shows the footer under the passage', (
    tester,
  ) async {
    await _sit(tester, withFieldsPart());
    expect(find.text('Bees are insects.'), findsOneWidget);
    expect(find.byType(IeltsPassageAttribution), findsOneWidget);
    expect(find.text('CC BY SA 4.0'), findsOneWidget);
  });

  testWidgets(
    'reading screen without the fields shows no footer and survives',
    (tester) async {
      await _sit(
        tester,
        IeltsPart.fromJson({'order': 1, 'passage_text': 'Plain text.'}),
      );
      expect(find.text('Plain text.'), findsOneWidget);
      expect(find.byType(IeltsPassageAttribution), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  final withFields = withFieldsPart();

  testWidgets('shows source, licence link, source link and adapted notice', (
    tester,
  ) async {
    final opened = <Uri>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: IeltsPassageAttribution(
            part: withFields,
            openLink: (uri) async {
              opened.add(uri);
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining("Wikipedia article 'Bee'"), findsOneWidget);
    expect(find.text('CC BY SA 4.0'), findsOneWidget);
    expect(find.textContaining('adaptedNotice'), findsOneWidget);

    final licence = find.widgetWithText(TextButton, 'CC BY SA 4.0');
    expect(tester.getSize(licence).height, greaterThanOrEqualTo(44));
    await tester.tap(licence);
    await tester.tap(find.widgetWithText(TextButton, 'ielts.viewSource'));
    expect(opened.map((u) => u.toString()), [
      'https://creativecommons.org/licenses/by-sa/4.0/',
      'https://en.wikipedia.org/wiki/Bee',
    ]);
  });

  test('an old backend without the fields yields no attribution', () {
    final part = IeltsPart.fromJson({'order': 1, 'passage_text': 'Text'});
    expect(part.hasAttribution, isFalse);
    expect(part.adapted, isFalse);
    expect(withFields.hasAttribution, isTrue);
  });
}
