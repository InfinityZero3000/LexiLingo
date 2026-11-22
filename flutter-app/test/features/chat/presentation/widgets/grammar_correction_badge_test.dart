import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import 'package:lexilingo_app/features/chat/domain/entities/educational_hints.dart';
import 'package:lexilingo_app/features/chat/presentation/widgets/educational_hints_widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FileLoader extends AssetLoader {
  const _FileLoader();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async =>
      jsonDecode(
            File('assets/i18n/${locale.languageCode}.json').readAsStringSync(),
          )
          as Map<String, dynamic>;
}

const _tense = GrammarCorrection(
  original: 'I has',
  corrected: 'I have',
  explanation: 'Với "I" ta dùng "have".',
  errorType: 'subject_verb_agreement',
);

Widget _host(
  GrammarCorrection correction, {
  VoidCallback? onSave,
  VoidCallback? onPractice,
  double textScale = 1,
}) {
  return EasyLocalization(
    supportedLocales: const [Locale('vi'), Locale('en')],
    path: 'unused',
    fallbackLocale: const Locale('en'),
    startLocale: const Locale('vi'),
    useOnlyLangCode: true,
    saveLocale: false,
    assetLoader: const _FileLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: context.locale,
        supportedLocales: context.supportedLocales,
        localizationsDelegates: context.localizationDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            child: GrammarCorrectionBadge(
              correction: correction,
              onSave: onSave,
              onPractice: onPractice,
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('shows wrong -> right, a translated label and one explanation', (
    tester,
  ) async {
    await tester.pumpWidget(_host(_tense));
    await tester.pumpAndSettle();

    expect(find.text('Gợi ý sửa'), findsOneWidget);
    expect(find.text('Hòa hợp chủ ngữ – động từ'), findsOneWidget);
    expect(find.text('I has'), findsOneWidget);
    expect(find.textContaining('I have', findRichText: true), findsOneWidget);
    expect(find.textContaining('ta dùng', findRichText: true), findsOneWidget);
    expect(find.text('subject_verb_agreement'), findsNothing);
    expect(find.byType(StatusPill), findsOneWidget);
  });

  testWidgets('old *_error codes are translated, not printed raw', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const GrammarCorrection(
          original: 'I go',
          corrected: 'I went',
          explanation: 'x',
          errorType: 'tense_error',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Thì động từ'), findsOneWidget);
    expect(find.text('tense_error'), findsNothing);
  });

  for (final type in ['other', 'vibes', null]) {
    testWidgets('label "$type" shows no pill', (tester) async {
      await tester.pumpWidget(
        _host(
          GrammarCorrection(
            original: 'I has',
            corrected: 'I have',
            explanation: 'x',
            errorType: type,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(StatusPill), findsNothing);
      expect(find.text('Gợi ý sửa'), findsOneWidget);
    });
  }

  for (final empty in [
    const GrammarCorrection(
      original: '',
      corrected: 'I have',
      explanation: 'x',
    ),
    const GrammarCorrection(
      original: 'I has',
      corrected: '  ',
      explanation: 'x',
    ),
  ]) {
    testWidgets('renders nothing when a side is empty', (tester) async {
      await tester.pumpWidget(_host(empty));
      await tester.pumpAndSettle();

      expect(find.text('Gợi ý sửa'), findsNothing);
      expect(find.byType(StatusPill), findsNothing);
    });
  }

  testWidgets('save button is labelled, tappable and at least 44x44', (
    tester,
  ) async {
    var saved = 0;
    await tester.pumpWidget(_host(_tense, onSave: () => saved++));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Lưu vào sổ lỗi'), findsOneWidget);
    final hit = tester.getSize(
      find
          .ancestor(
            of: find.byIcon(Icons.bookmark_add_outlined),
            matching: find.byType(ConstrainedBox),
          )
          .first,
    );
    expect(hit.width, greaterThanOrEqualTo(44));
    expect(hit.height, greaterThanOrEqualTo(44));

    await tester.tap(find.byIcon(Icons.bookmark_add_outlined));
    expect(saved, 1);
  });

  testWidgets('practice chip is hidden for spelling and punctuation', (
    tester,
  ) async {
    for (final type in ['spelling', 'punctuation']) {
      await tester.pumpWidget(
        _host(
          GrammarCorrection(
            original: 'recieve',
            corrected: 'receive',
            explanation: 'x',
            errorType: type,
          ),
          onPractice: () {},
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ActionChip), findsNothing, reason: type);
    }

    await tester.pumpWidget(_host(_tense, onPractice: () {}));
    await tester.pumpAndSettle();
    expect(find.byType(ActionChip), findsOneWidget);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets('does not overflow at 375px wide, text scale $scale', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(375, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        _host(
          const GrammarCorrection(
            original: 'yesterday I go to the dentist with my brother',
            corrected: 'yesterday I went to the dentist with my brother',
            explanation:
                'Có "yesterday" thì dùng thì quá khứ đơn: "went", không dùng "go".',
            errorType: 'subject_verb_agreement',
          ),
          onSave: () {},
          onPractice: () {},
          textScale: scale,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  }
}
