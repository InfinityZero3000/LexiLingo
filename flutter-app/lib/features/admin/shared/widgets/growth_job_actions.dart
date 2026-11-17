import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';

/// Status text to pill tone for the agent job screens.
StatusTone jobStatusTone(String status) => switch (status) {
  'completed' || 'applied' => StatusTone.success,
  'failed' => StatusTone.danger,
  'sending' || 'preview_ready' || 'applying' => StatusTone.warning,
  'cancelled' => StatusTone.neutral,
  _ => StatusTone.info,
};

/// Applying a job writes to live data or reaches many users, so it asks for a
/// typed word; cancelling only needs a plain confirm.
const kApplyWord = 'APPLY';

Future<bool> confirmApply(
  BuildContext context, {
  required String title,
  required String body,
}) => showConfirm(
  context,
  title: title,
  message: body,
  confirmLabel: 'adminGrowth.jobs.apply'.tr(),
  danger: true,
  requireText: kApplyWord,
);

Future<bool> confirmCancel(
  BuildContext context, {
  required String title,
  required String body,
}) => showConfirm(
  context,
  title: title,
  message: body,
  confirmLabel: 'adminGrowth.jobs.cancel'.tr(),
  cancelLabel: 'adminGrowth.jobs.keep'.tr(),
);

/// Retry / cancel / apply row. A button is only shown when the job's state
/// allows it and the admin's role permits the write.
class GrowthJobActions extends StatelessWidget {
  const GrowthJobActions({
    super.key,
    this.onRetry,
    this.onCancel,
    this.onApply,
  });

  final VoidCallback? onRetry;
  final VoidCallback? onCancel;
  final VoidCallback? onApply;

  @override
  Widget build(BuildContext context) {
    if (onRetry == null && onCancel == null && onApply == null) {
      return const SizedBox.shrink();
    }
    const min = Size(kMinTapTarget, kMinTapTarget);
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Wrap(
        alignment: WrapAlignment.end,
        spacing: AppSpacing.xs,
        runSpacing: AppSpacing.xs,
        children: [
          if (onRetry != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: min),
              onPressed: onRetry,
              child: Text('adminGrowth.jobs.retry'.tr()),
            ),
          if (onCancel != null)
            TextButton(
              style: TextButton.styleFrom(minimumSize: min),
              onPressed: onCancel,
              child: Text('adminGrowth.jobs.cancel'.tr()),
            ),
          if (onApply != null)
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: min),
              onPressed: onApply,
              child: Text('adminGrowth.jobs.apply'.tr()),
            ),
        ],
      ),
    );
  }
}
