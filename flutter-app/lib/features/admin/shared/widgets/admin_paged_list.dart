import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/core/widgets/paginated_list_view.dart';
import 'admin_error_view.dart';

/// A [PageResult] from a response body, whatever key the list sits under.
///
/// `getData` has already removed the `{data}` envelope, so a list can arrive as
/// the body itself, or inside `{courses: [...]}`, `{items: [...]}` and so on.
PageResult<T> adminPage<T>(
  dynamic body,
  T Function(Map<String, dynamic>) parse, {
  List<String> keys = const [],
}) {
  List<dynamic> items = const [];
  int? total;
  if (body is List) {
    items = body;
  } else if (body is Map) {
    for (final key in [...keys, 'items', 'data', 'results']) {
      if (body[key] is List) {
        items = body[key] as List;
        break;
      }
    }
    final pagination = body['pagination'];
    total =
        ((pagination is Map ? pagination['total'] : null) ??
                body['total'] ??
                body['count'])
            ?.toInt();
  }
  return PageResult(
    items: [
      for (final e in items)
        if (e is Map) parse(Map<String, dynamic>.from(e)),
    ],
    total: total,
  );
}

/// One admin list: the controller plus the raw error behind it.
///
/// The controller reduces every failure to one message; admin screens also
/// need to know a 403 or a 503 from the rest, so the last raw error is kept.
class AdminPager<T> {
  AdminPager({
    required Future<PageResult<T>> Function(
      PageRequest request,
      Map<String, Object?> filters,
    )
    load,
    int pageSize = 30,
  }) {
    controller = PaginatedListController<T>(
      pageSize: pageSize,
      fetcher: FunctionPageFetcher<T>((request, filters) async {
        try {
          final result = await load(request, filters);
          lastError = null;
          return result;
        } catch (e) {
          lastError = e;
          rethrow;
        }
      }),
    );
  }

  late final PaginatedListController<T> controller;
  Object? lastError;

  void dispose() => controller.dispose();
}

/// [PaginatedListView] that shows a 403 or a 503 as the expected state it is.
class AdminPagedList<T> extends StatelessWidget {
  const AdminPagedList({
    super.key,
    required this.pager,
    required this.itemBuilder,
    this.header,
    this.emptyTitle,
    this.emptyIcon,
    this.padding = const EdgeInsets.all(16),
  });

  final AdminPager<T> pager;
  final Widget Function(BuildContext, T, int) itemBuilder;
  final Widget? header;
  final String? emptyTitle;
  final IconData? emptyIcon;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final c = pager.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final error = pager.lastError;
        if (c.status == ListStatus.error && c.items.isEmpty && error != null) {
          return AdminErrorView(error: error, onRetry: c.refresh);
        }
        return Column(
          children: [
            ?header,
            Expanded(
              child: PaginatedListView<T>(
                controller: c,
                itemBuilder: itemBuilder,
                emptyTitle: emptyTitle,
                emptyIcon: emptyIcon,
                padding: padding,
              ),
            ),
          ],
        );
      },
    );
  }
}
