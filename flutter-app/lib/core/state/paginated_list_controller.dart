import 'package:flutter/foundation.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/network/envelope.dart';

/// The three paging styles the backend uses.
enum PaginationStyle {
  pageSize('page', 'page_size'),
  perPage('page', 'per_page'),
  limitOffset('offset', 'limit');

  const PaginationStyle(this._first, this._second);
  final String _first;
  final String _second;

  /// Query parameters for [request] in this style.
  Map<String, String> query(PageRequest request) => switch (this) {
    PaginationStyle.limitOffset => {
      _first: '${request.offset}',
      _second: '${request.size}',
    },
    _ => {_first: '${request.page}', _second: '${request.size}'},
  };
}

class PageRequest {
  const PageRequest({required this.index, required this.size});

  /// Zero-based page number.
  final int index;
  final int size;

  /// One-based, for `page=` style endpoints.
  int get page => index + 1;
  int get offset => index * size;
  int get limit => size;
}

class PageResult<T> {
  const PageResult({required this.items, this.total, this.hasMore});

  /// Maps any list body (see [extractPage]) through [parse].
  factory PageResult.fromBody(dynamic body, T Function(dynamic) parse) {
    final page = extractPage(unwrapEnvelopeIfNested(body));
    return PageResult(items: page.items.map(parse).toList(), total: page.total);
  }

  final List<T> items;
  final int? total;
  final bool? hasMore;
}

/// `{data: {items: [...]}}` is a wrapped page; `{data: [...]}` is already one.
dynamic unwrapEnvelopeIfNested(dynamic body) {
  if (body is Map && body['data'] is Map) return unwrapEnvelope(body);
  return body;
}

abstract class PageFetcher<T> {
  Future<PageResult<T>> fetch(
    PageRequest request,
    Map<String, Object?> filters,
  );
}

/// A [PageFetcher] from a closure, for screens that need no class of their own.
class FunctionPageFetcher<T> implements PageFetcher<T> {
  const FunctionPageFetcher(this._fetch);

  final Future<PageResult<T>> Function(
    PageRequest request,
    Map<String, Object?> filters,
  )
  _fetch;

  @override
  Future<PageResult<T>> fetch(
    PageRequest request,
    Map<String, Object?> filters,
  ) => _fetch(request, filters);
}

enum ListStatus { idle, loading, ready, error }

/// One list, its filters and its paging. A newer request supersedes an older
/// one, so a slow first page cannot overwrite a fresh filter's result.
class PaginatedListController<T> extends ChangeNotifier {
  PaginatedListController({
    required this.fetcher,
    this.pageSize = 20,
    Map<String, Object?> filters = const {},
  }) : _filters = Map.of(filters);

  final PageFetcher<T> fetcher;
  final int pageSize;

  final List<T> _items = [];
  Map<String, Object?> _filters;
  ListStatus _status = ListStatus.idle;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _nextIndex = 0;
  int _generation = 0;
  bool _disposed = false;
  UiText? _error;
  UiText? _moreError;

  List<T> get items => List.unmodifiable(_items);
  Map<String, Object?> get filters => Map.unmodifiable(_filters);
  ListStatus get status => _status;
  bool get isLoading => _status == ListStatus.loading;
  bool get isLoadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  bool get isEmpty => _status == ListStatus.ready && _items.isEmpty;

  /// Set when the first page fails.
  UiText? get error => _error;

  /// Set when a later page fails; the items already loaded stay.
  UiText? get loadMoreError => _moreError;

  Future<void> refresh() async {
    final generation = ++_generation;
    _loadingMore = false;
    _moreError = null;
    if (_items.isEmpty || _status == ListStatus.error) {
      _status = ListStatus.loading;
    }
    _error = null;
    _notify();
    try {
      final result = await fetcher.fetch(
        PageRequest(index: 0, size: pageSize),
        _filters,
      );
      if (generation != _generation) return;
      _items
        ..clear()
        ..addAll(result.items);
      _nextIndex = 1;
      _hasMore = _hasMoreAfter(result, 0);
      _status = ListStatus.ready;
    } catch (e) {
      if (generation != _generation) return;
      _error = _toText(e);
      _status = ListStatus.error;
    }
    _notify();
  }

  Future<void> loadMore() async {
    if (_status != ListStatus.ready || _loadingMore || !_hasMore) return;
    final generation = _generation;
    _loadingMore = true;
    _moreError = null;
    _notify();
    try {
      final index = _nextIndex;
      final result = await fetcher.fetch(
        PageRequest(index: index, size: pageSize),
        _filters,
      );
      if (generation != _generation) return;
      _items.addAll(result.items);
      _nextIndex = index + 1;
      _hasMore = _hasMoreAfter(result, index);
    } catch (e) {
      if (generation != _generation) return;
      _moreError = _toText(e);
    }
    _loadingMore = false;
    _notify();
  }

  /// Replaces the filters and reloads from the first page.
  Future<void> setFilters(Map<String, Object?> filters) {
    _filters = Map.of(filters);
    _items.clear();
    _hasMore = true;
    _status = ListStatus.idle;
    return refresh();
  }

  /// Changes one filter; a null value removes it.
  Future<void> setFilter(String key, Object? value) {
    final next = Map.of(_filters);
    if (value == null) {
      next.remove(key);
    } else {
      next[key] = value;
    }
    return setFilters(next);
  }

  /// Applies a change to a loaded item without refetching.
  void replaceWhere(bool Function(T) test, T Function(T) update) {
    for (var i = 0; i < _items.length; i++) {
      if (test(_items[i])) _items[i] = update(_items[i]);
    }
    _notify();
  }

  void removeWhere(bool Function(T) test) {
    _items.removeWhere(test);
    _notify();
  }

  bool _hasMoreAfter(PageResult<T> result, int index) {
    final explicit = result.hasMore;
    if (explicit != null) return explicit;
    final total = result.total;
    if (total != null) return (index * pageSize) + result.items.length < total;
    return result.items.length >= pageSize;
  }

  UiText _toText(Object e) => e is Failure
      ? UiText.failure(e)
      : const UiText.key('errors.genericRetry');

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
