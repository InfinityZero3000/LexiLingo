import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/empty_state_widget.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';
import '../../core/network/admin_api_error.dart';

/// A failed admin call as a screen body. 403 (permission the role lacks) and
/// 503 (the feature's flag is off) are expected states, so they get their own
/// message and no retry; anything else is an error with a retry.
class AdminErrorView extends StatelessWidget {
  const AdminErrorView({super.key, required this.error, this.onRetry});

  final Object error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final e = AdminApiError.from(error);
    switch (e.kind) {
      case AdminErrorKind.forbidden:
        return EmptyStateWidget(
          icon: Icons.lock_outline,
          title: 'admin.access.forbiddenTitle'.tr(),
          description: 'admin.access.forbiddenBody'.tr(),
        );
      case AdminErrorKind.featureOff:
        return EmptyStateWidget(
          icon: Icons.toggle_off_outlined,
          title: 'admin.access.featureOffTitle'.tr(),
          description: 'admin.access.featureOffBody'.tr(),
        );
      default:
        return ErrorDisplayWidget(
          errorType: switch (e.kind) {
            AdminErrorKind.network => ErrorType.network,
            AdminErrorKind.server => ErrorType.server,
            AdminErrorKind.unauthorized => ErrorType.unauthorized,
            AdminErrorKind.notFound => ErrorType.notFound,
            _ => ErrorType.unknown,
          },
          customMessage: e.message.resolve(),
          onRetry: onRetry,
        );
    }
  }
}
