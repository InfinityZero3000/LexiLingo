import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';

Widget host(Widget child) => MaterialApp(
  theme: AppTheme.lightTheme,
  home: Scaffold(body: child),
);

void main() {
  group('showConfirm', () {
    Future<bool?> open(
      WidgetTester tester, {
      bool danger = false,
      String? requireText,
    }) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showConfirm(
                context,
                title: 'Delete?',
                message: 'Gone for good',
                confirmLabel: 'Delete',
                cancelLabel: 'Keep',
                danger: danger,
                requireText: requireText,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('confirm resolves true, cancel resolves false', (tester) async {
      bool? result;
      await tester.pumpWidget(
        host(
          Builder(
            builder: (context) => TextButton(
              onPressed: () async => result = await showConfirm(
                context,
                title: 'Sure?',
                confirmLabel: 'Yes',
                cancelLabel: 'No',
              ),
              child: const Text('open'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Yes'));
      await tester.pumpAndSettle();
      expect(result, isTrue);

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('No'));
      await tester.pumpAndSettle();
      expect(result, isFalse);
    });

    testWidgets('requireText keeps confirm disabled until it is typed', (
      tester,
    ) async {
      await open(tester, danger: true, requireText: 'DELETE');
      FilledButton confirm() => tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Delete'),
      );
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'delet');
      await tester.pump();
      expect(confirm().onPressed, isNull);

      await tester.enterText(find.byType(TextField), 'DELETE');
      await tester.pump();
      expect(confirm().onPressed, isNotNull);
    });

    testWidgets('a danger sheet is not dismissed by tapping outside', (
      tester,
    ) async {
      await open(tester, danger: true);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('Delete?'), findsOneWidget);
    });
  });

  group('ViewStateBody', () {
    Widget body({bool loading = false, bool data = false, UiText? error}) =>
        host(
          ViewStateBody(
            isLoading: loading,
            hasData: data,
            error: error,
            onRetry: () {},
            emptyTitle: 'Nothing',
            builder: (_) => const Text('content'),
          ),
        );

    testWidgets('loading shows a skeleton', (tester) async {
      await tester.pumpWidget(body(loading: true));
      expect(find.byType(SkeletonList), findsOneWidget);
    });

    testWidgets('error shows retry', (tester) async {
      await tester.pumpWidget(body(error: const UiText.raw('Server is down')));
      expect(find.byType(ErrorDisplayWidget), findsOneWidget);
    });

    testWidgets('empty shows the empty state', (tester) async {
      await tester.pumpAndSettle();
      await tester.pumpWidget(body());
      await tester.pumpAndSettle();
      expect(find.text('Nothing'), findsOneWidget);
    });

    testWidgets('data wins over loading and error', (tester) async {
      await tester.pumpWidget(
        body(loading: true, data: true, error: const UiText.raw('x')),
      );
      expect(find.text('content'), findsOneWidget);
    });
  });

  testWidgets('ErrorDisplayWidget.fromFailure maps the failure type', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(ErrorDisplayWidget.fromFailure(const NetworkFailure('x'))),
    );
    expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    await tester.pumpWidget(
      host(ErrorDisplayWidget.fromFailure(const NotFoundFailure('x'))),
    );
    expect(find.byIcon(Icons.search_off_rounded), findsOneWidget);
  });

  group('PaginatedListView', () {
    PaginatedListController<int> controller(int total, {bool fail = false}) =>
        PaginatedListController<int>(
          pageSize: 20,
          fetcher: FunctionPageFetcher((r, f) async {
            if (fail) throw const NetworkFailure('down');
            final end = (r.offset + r.size).clamp(0, total);
            return PageResult(
              items: [for (var i = r.offset; i < end; i++) i],
              total: total,
            );
          }),
        );

    Widget view(PaginatedListController<int> c) => host(
      PaginatedListView<int>(
        controller: c,
        emptyTitle: 'No rows',
        itemBuilder: (_, item, __) =>
            SizedBox(height: 60, child: Text('row $item')),
      ),
    );

    testWidgets('loads the first page on its own', (tester) async {
      final c = controller(5);
      await tester.pumpWidget(view(c));
      await tester.pumpAndSettle();
      expect(find.text('row 0'), findsOneWidget);
      expect(find.text('row 4'), findsOneWidget);
    });

    testWidgets('empty list shows the empty title', (tester) async {
      await tester.pumpWidget(view(controller(0)));
      await tester.pumpAndSettle();
      expect(find.text('No rows'), findsOneWidget);
    });

    testWidgets('a failed load shows the error widget', (tester) async {
      await tester.pumpWidget(view(controller(5, fail: true)));
      await tester.pumpAndSettle();
      expect(find.byType(ErrorDisplayWidget), findsOneWidget);
    });

    testWidgets('scrolling near the end loads the next page', (tester) async {
      final c = controller(45);
      await tester.pumpWidget(view(c));
      await tester.pumpAndSettle();
      expect(c.items.length, 20);
      await tester.drag(find.byType(ListView), const Offset(0, -2000));
      await tester.pumpAndSettle();
      expect(c.items.length, greaterThan(20));
    });
  });

  group('DebouncedSearchField', () {
    testWidgets('reports once after the pause, not per key', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(host(DebouncedSearchField(onChanged: seen.add)));
      await tester.enterText(find.byType(TextField), 'a');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byType(TextField), 'ab');
      await tester.pump(const Duration(milliseconds: 399));
      expect(seen, isEmpty);
      await tester.pump(const Duration(milliseconds: 2));
      expect(seen, ['ab']);
    });

    testWidgets('clear reports an empty query immediately', (tester) async {
      final seen = <String>[];
      await tester.pumpWidget(host(DebouncedSearchField(onChanged: seen.add)));
      await tester.enterText(find.byType(TextField), 'cat');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pump();
      expect(seen, ['cat', '']);
    });
  });

  group('filters', () {
    const options = [
      FilterOption(value: 1, label: 'One'),
      FilterOption(value: 2, label: 'Two'),
    ];

    testWidgets('FilterChipBar selects and clears when allowed', (
      tester,
    ) async {
      int? picked = 1;
      await tester.pumpWidget(
        host(
          FilterChipBar<int>(
            options: options,
            selected: 1,
            allowClear: true,
            onSelected: (v) => picked = v,
          ),
        ),
      );
      await tester.tap(find.text('Two'));
      expect(picked, 2);
      await tester.tap(find.text('One'));
      expect(picked, isNull);
    });

    testWidgets('SegmentedTabs reports the tapped segment', (tester) async {
      var picked = 1;
      await tester.pumpWidget(
        host(
          SegmentedTabs<int>(
            options: options,
            selected: 1,
            onChanged: (v) => picked = v,
          ),
        ),
      );
      await tester.tap(find.text('Two'));
      expect(picked, 2);
    });
  });

  group('StatCard and StatusPill', () {
    testWidgets('StatCard shows label, value, trend and note', (tester) async {
      await tester.pumpWidget(
        host(
          const StatCard(
            label: 'Active users',
            value: '1,204',
            trend: '+8%',
            note: 'vs last week',
          ),
        ),
      );
      expect(find.text('Active users'), findsOneWidget);
      expect(find.text('1,204'), findsOneWidget);
      expect(find.text('+8%'), findsOneWidget);
    });

    testWidgets('StatCard loading hides the value', (tester) async {
      await tester.pumpWidget(
        host(const StatCard(label: 'L', value: 'V', loading: true)),
      );
      expect(find.text('V'), findsNothing);
      expect(find.byType(SkeletonBox), findsWidgets);
    });

    testWidgets('StatusPill renders every tone', (tester) async {
      for (final tone in StatusTone.values) {
        await tester.pumpWidget(host(StatusPill(label: tone.name, tone: tone)));
        expect(find.text(tone.name), findsOneWidget);
      }
    });
  });

  testWidgets('AppTextField shows label, error and forwards typing', (
    tester,
  ) async {
    var typed = '';
    await tester.pumpWidget(
      host(
        AppTextField(
          label: 'Email',
          errorText: 'Required',
          onChanged: (v) => typed = v,
        ),
      ),
    );
    expect(find.text('Email'), findsOneWidget);
    expect(find.text('Required'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'x@y.z');
    expect(typed, 'x@y.z');
  });
}
