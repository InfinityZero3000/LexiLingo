import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

/// Picks one of loading, error, empty or data for a screen body.
///
/// Loading and error only replace the data while there is none, so a refresh
/// or a failed reload never blanks a list the reader is looking at.
class ViewStateBody extends StatelessWidget {
  const ViewStateBody({
    super.key,
    required this.isLoading,
    required this.hasData,
    required this.builder,
    this.error,
    this.onRetry,
    this.loading,
    this.empty,
    this.emptyTitle,
    this.emptyDescription,
    this.emptyIcon,
  });

  final bool isLoading;
  final bool hasData;
  final UiText? error;
  final VoidCallback? onRetry;
  final WidgetBuilder builder;
  final Widget? loading;
  final Widget? empty;
  final String? emptyTitle;
  final String? emptyDescription;
  final IconData? emptyIcon;

  @override
  Widget build(BuildContext context) {
    if (!hasData && isLoading) {
      return loading ?? const SkeletonList();
    }
    if (!hasData && error != null) {
      return ErrorDisplayWidget.fromMessage(
        message: error!.resolve(),
        onRetry: onRetry,
      );
    }
    if (!hasData) {
      return empty ??
          EmptyStateWidget(
            icon: emptyIcon ?? Icons.inbox_outlined,
            title: emptyTitle ?? 'common.noData'.tr(),
            description: emptyDescription,
          );
    }
    return builder(context);
  }
}

/// Inline strip for a failed reload while data is still showing.
class InlineErrorBar extends StatelessWidget {
  const InlineErrorBar({super.key, required this.message, this.onRetry});

  final UiText message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      color: scheme.errorContainer,
      child: Row(
        children: [
          Expanded(
            child: Text(
              message.resolve(),
              style: TextStyle(color: scheme.onErrorContainer),
            ),
          ),
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: onRetry,
              child: Text('common.retry'.tr()),
            ),
        ],
      ),
    );
  }
}
