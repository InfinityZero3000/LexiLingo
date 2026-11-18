import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/paginated_list_view.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import '../../core/network/admin_api_error.dart';
import 'admin_error_view.dart';

/// A [PageFetcher] for admin lists. It remembers the last failure so a 403 or
/// 503 can be shown as the expected state it is, and exposes the server's total
/// for a "N results" line.
class AdminPageFetcher<T> implements PageFetcher<T> {
  AdminPageFetcher(this._fetch);

  final Future<PageResult<T>> Function(
    PageRequest request,
    Map<String, Object?> filters,
  )
  _fetch;

  AdminApiError? lastError;
  final total = ValueNotifier<int?>(null);

  @override
  Future<PageResult<T>> fetch(
    PageRequest request,
    Map<String, Object?> filters,
  ) async {
    try {
      final result = await _fetch(request, filters);
      lastError = null;
      if (result.total != null) total.value = result.total;
      return result;
    } catch (e) {
      final error = AdminApiError.from(e);
      lastError = error;
      throw switch (error.kind) {
        AdminErrorKind.network => const NetworkFailure(),
        AdminErrorKind.server => const ServerFailure(),
        AdminErrorKind.unauthorized => const UnauthorizedFailure(),
        AdminErrorKind.forbidden => const PermissionFailure(),
        AdminErrorKind.notFound => const NotFoundFailure(),
        _ => UnexpectedFailure(error.message.resolve()),
      };
    }
  }
}

/// [PaginatedListView] for an admin list: skeleton, empty, error with retry,
/// pull to refresh and load more, plus a plain "no access" or "turned off"
/// state when the server answers 403 or 503.
class AdminPagedListView<T> extends StatelessWidget {
  const AdminPagedListView({
    super.key,
    required this.controller,
    required this.fetcher,
    required this.itemBuilder,
    this.emptyTitle,
    this.emptyDescription,
    this.emptyIcon,
    this.padding = const EdgeInsets.fromLTRB(
      AppSpacing.lg,
      AppSpacing.sm,
      AppSpacing.lg,
      AppSpacing.xxl,
    ),
    this.separatorBuilder,
  });

  final PaginatedListController<T> controller;
  final AdminPageFetcher<T> fetcher;
  final Widget Function(BuildContext context, T item, int index) itemBuilder;
  final String? emptyTitle;
  final String? emptyDescription;
  final IconData? emptyIcon;
  final EdgeInsetsGeometry padding;
  final IndexedWidgetBuilder? separatorBuilder;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final last = fetcher.lastError;
        final expected =
            controller.status == ListStatus.error &&
            controller.items.isEmpty &&
            last != null &&
            (last.isForbidden || last.isFeatureOff);
        if (expected) {
          return AdminErrorView(error: last, onRetry: controller.refresh);
        }
        return PaginatedListView<T>(
          controller: controller,
          itemBuilder: itemBuilder,
          padding: padding,
          separatorBuilder: separatorBuilder,
          emptyTitle: emptyTitle,
          emptyDescription: emptyDescription,
          emptyIcon: emptyIcon,
          loading: const SkeletonList(),
        );
      },
    );
  }
}

/// Loads one value and shows it with the same states as a list: skeleton,
/// error (403/503 as expected states) and the data.
class AdminFutureView<T> extends StatelessWidget {
  const AdminFutureView({
    super.key,
    required this.future,
    required this.builder,
    this.onRetry,
  });

  final Future<T> future;
  final Widget Function(BuildContext context, T data) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return AdminErrorView(error: snapshot.error!, onRetry: onRetry);
        }
        if (!snapshot.hasData) return const SkeletonList();
        return builder(context, snapshot.data as T);
      },
    );
  }
}
