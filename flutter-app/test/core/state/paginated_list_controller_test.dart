import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';

PaginatedListController<int> controllerOver(
  int total, {
  int pageSize = 3,
  Future<void> Function(PageRequest)? before,
  List<Map<String, Object?>>? seenFilters,
}) {
  return PaginatedListController<int>(
    pageSize: pageSize,
    fetcher: FunctionPageFetcher((request, filters) async {
      seenFilters?.add(filters);
      await before?.call(request);
      final start = request.offset;
      final end = (start + request.size).clamp(0, total);
      return PageResult(
        items: [for (var i = start; i < end; i++) i],
        total: total,
      );
    }),
  );
}

void main() {
  test('refresh loads the first page', () async {
    final c = controllerOver(7);
    await c.refresh();
    expect(c.items, [0, 1, 2]);
    expect(c.status, ListStatus.ready);
    expect(c.hasMore, isTrue);
  });

  test('loadMore appends until total is reached, then stops', () async {
    final c = controllerOver(7);
    await c.refresh();
    await c.loadMore();
    await c.loadMore();
    expect(c.items, [0, 1, 2, 3, 4, 5, 6]);
    expect(c.hasMore, isFalse);
    await c.loadMore();
    expect(c.items.length, 7);
  });

  test('refresh replaces what was loaded', () async {
    final c = controllerOver(7);
    await c.refresh();
    await c.loadMore();
    await c.refresh();
    expect(c.items, [0, 1, 2]);
  });

  test('without a total, a short page means no more', () async {
    final c = PaginatedListController<int>(
      pageSize: 3,
      fetcher: FunctionPageFetcher(
        (r, f) async => PageResult(items: r.index == 0 ? [1, 2, 3] : [4]),
      ),
    );
    await c.refresh();
    expect(c.hasMore, isTrue);
    await c.loadMore();
    expect(c.hasMore, isFalse);
  });

  test('an empty result is isEmpty, not an error', () async {
    final c = controllerOver(0);
    await c.refresh();
    expect(c.isEmpty, isTrue);
    expect(c.error, isNull);
  });

  test('a failed first page sets error and retry recovers', () async {
    var fail = true;
    final c = PaginatedListController<int>(
      fetcher: FunctionPageFetcher((r, f) async {
        if (fail) throw const NetworkFailure('down');
        return const PageResult(items: [1], total: 1);
      }),
    );
    await c.refresh();
    expect(c.status, ListStatus.error);
    expect(c.error, isNotNull);
    fail = false;
    await c.refresh();
    expect(c.status, ListStatus.ready);
    expect(c.items, [1]);
  });

  test(
    'a failed later page keeps the items and reports loadMoreError',
    () async {
      final c = PaginatedListController<int>(
        pageSize: 2,
        fetcher: FunctionPageFetcher((r, f) async {
          if (r.index > 0) throw const ServerFailure('boom');
          return const PageResult(items: [1, 2], total: 10);
        }),
      );
      await c.refresh();
      await c.loadMore();
      expect(c.items, [1, 2]);
      expect(c.loadMoreError, isNotNull);
      expect(c.status, ListStatus.ready);
    },
  );

  test('setFilter refetches from the first page with the filter', () async {
    final seen = <Map<String, Object?>>[];
    final c = controllerOver(7, seenFilters: seen);
    await c.refresh();
    await c.loadMore();
    await c.setFilter('role', 1);
    expect(c.items, [0, 1, 2]);
    expect(seen.last, {'role': 1});
    await c.setFilter('role', null);
    expect(seen.last, isEmpty);
  });

  test('a slow older request cannot overwrite a newer one', () async {
    final gate = Completer<void>();
    var calls = 0;
    final c = PaginatedListController<int>(
      fetcher: FunctionPageFetcher((r, f) async {
        final call = ++calls;
        if (call == 1) await gate.future;
        return PageResult(items: [call], total: 1);
      }),
    );
    final first = c.refresh();
    await c.refresh();
    gate.complete();
    await first;
    expect(c.items, [2]);
  });

  test('PaginationStyle builds each query shape', () {
    const r = PageRequest(index: 2, size: 20);
    expect(PaginationStyle.pageSize.query(r), {'page': '3', 'page_size': '20'});
    expect(PaginationStyle.perPage.query(r), {'page': '3', 'per_page': '20'});
    expect(PaginationStyle.limitOffset.query(r), {
      'offset': '40',
      'limit': '20',
    });
  });

  test('PageResult.fromBody reads wrapped and raw pages', () {
    final wrapped = PageResult<int>.fromBody({
      'data': {
        'items': [1, 2],
        'total': 5,
      },
      'meta': {},
    }, (e) => e as int);
    expect(wrapped.items, [1, 2]);
    expect(wrapped.total, 5);
    final raw = PageResult<int>.fromBody([3], (e) => e as int);
    expect(raw.items, [3]);
  });
}
