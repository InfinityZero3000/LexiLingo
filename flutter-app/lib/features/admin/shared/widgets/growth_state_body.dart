import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'admin_error_view.dart';

/// Loading, error (403/503 as normal states), empty or data for an admin list.
/// Loading and error only replace the body while there is no data, so a failed
/// refresh never blanks what the admin is looking at.
class GrowthStateBody extends StatelessWidget {
  const GrowthStateBody({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.builder,
    this.error,
    this.onRetry,
    this.emptyTitleKey = 'adminGrowth.common.empty',
    this.emptyIcon = Icons.inbox_outlined,
  });

  final bool isLoading;
  final bool hasData;
  final Object? error;
  final VoidCallback? onRetry;
  final WidgetBuilder builder;
  final String emptyTitleKey;
  final IconData emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (!hasData && isLoading) return const SkeletonList();
    if (!hasData && error != null) {
      return _scrollable(AdminErrorView(error: error!, onRetry: onRetry));
    }
    if (!hasData) {
      return _scrollable(
        EmptyStateWidget(icon: emptyIcon, title: emptyTitleKey.tr()),
      );
    }
    return builder(context);
  }

  /// Keeps pull-to-refresh working when there is nothing to scroll.
  Widget _scrollable(Widget child) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: constraints.maxHeight),
        child: Center(child: child),
      ),
    ),
  );
}
