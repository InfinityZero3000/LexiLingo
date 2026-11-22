import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/view_state.dart';

/// Renders a [PaginatedListController]: skeleton, error with retry, empty,
/// pull to refresh and load more near the end.
class PaginatedListView<T> extends StatefulWidget {
  const PaginatedListView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.separatorBuilder,
    this.loading,
    this.empty,
    this.emptyTitle,
    this.emptyDescription,
    this.emptyIcon,
    this.header,
    this.autoLoad = true,
    this.loadMoreThreshold = 240,
  });

  final PaginatedListController<T> controller;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder? separatorBuilder;
  final Widget? loading;
  final Widget? empty;
  final String? emptyTitle;
  final String? emptyDescription;
  final IconData? emptyIcon;
  final Widget? header;
  final bool autoLoad;
  final double loadMoreThreshold;

  @override
  State<PaginatedListView<T>> createState() => _PaginatedListViewState<T>();
}

class _PaginatedListViewState<T> extends State<PaginatedListView<T>> {
  final _scroll = ScrollController();

  PaginatedListController<T> get _c => widget.controller;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
    if (widget.autoLoad && _c.status == ListStatus.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _c.refresh();
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels <=
        widget.loadMoreThreshold) {
      _c.loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final items = _c.items;
        return ViewStateBody(
          isLoading: _c.isLoading || _c.status == ListStatus.idle,
          hasData: items.isNotEmpty,
          error: _c.error,
          onRetry: _c.refresh,
          loading: widget.loading,
          empty: widget.empty,
          emptyTitle: widget.emptyTitle,
          emptyDescription: widget.emptyDescription,
          emptyIcon: widget.emptyIcon,
          builder: (context) => RefreshIndicator(
            onRefresh: _c.refresh,
            child: ListView.separated(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: widget.padding,
              itemCount: items.length + 1 + (widget.header == null ? 0 : 1),
              separatorBuilder:
                  widget.separatorBuilder ??
                  (_, __) => const SizedBox(height: AppSpacing.md),
              itemBuilder: (context, i) {
                if (widget.header != null) {
                  if (i == 0) return widget.header!;
                  i -= 1;
                }
                if (i == items.length) return _footer(context);
                return widget.itemBuilder(context, items[i], i);
              },
            ),
          ),
        );
      },
    );
  }

  Widget _footer(BuildContext context) {
    if (_c.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
        child: Center(
          child: SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final moreError = _c.loadMoreError;
    if (moreError != null) {
      return InlineErrorBar(message: moreError, onRetry: _c.loadMore);
    }
    if (_c.hasMore) {
      return Center(
        child: TextButton(
          style: TextButton.styleFrom(
            minimumSize: const Size(kMinTapTarget, kMinTapTarget),
          ),
          onPressed: _c.loadMore,
          child: Text('coreKit.loadMore'.tr()),
        ),
      );
    }
    return const SizedBox(height: AppSpacing.sm);
  }
}
