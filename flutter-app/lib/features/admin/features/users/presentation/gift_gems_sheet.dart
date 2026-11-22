import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import '../../../core/network/admin_api_error.dart';
import '../../gem_ledger/data/gem_models.dart';

/// Shortest reason the backend accepts for a gift (`min_length=5`).
const giftReasonMinLength = 5;

/// Form for gifting gems to one learner. [loadUsage] says how many gems the
/// admin may still give; [send] does the gift and throws if it fails. Resolves
/// to true when the gift went through.
Future<bool> showGiftGemsSheet(
  BuildContext context, {
  required String recipientName,
  required Future<GemUsage> Function() loadUsage,
  required Future<void> Function(int amount, String reason) send,
}) async {
  final sent = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => GiftGemsSheet(
      recipientName: recipientName,
      loadUsage: loadUsage,
      send: send,
    ),
  );
  return sent ?? false;
}

class GiftGemsSheet extends StatefulWidget {
  const GiftGemsSheet({
    super.key,
    required this.recipientName,
    required this.loadUsage,
    required this.send,
  });

  final String recipientName;
  final Future<GemUsage> Function() loadUsage;
  final Future<void> Function(int amount, String reason) send;

  @override
  State<GiftGemsSheet> createState() => _GiftGemsSheetState();
}

class _GiftGemsSheetState extends State<GiftGemsSheet> {
  final _amount = TextEditingController();
  final _reason = TextEditingController();
  late final Future<GemUsage> _usage = widget.loadUsage();
  String? _amountError;
  String? _reasonError;
  String? _failure;
  bool _sending = false;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit(GemUsage? usage) async {
    final amount = int.tryParse(_amount.text.trim());
    final ceiling = usage?.giftCeiling;
    final reason = _reason.text.trim();
    setState(() {
      _failure = null;
      _amountError = ceiling == 0
          ? 'admin.users.gift.budgetUsed'.tr()
          : (amount == null || amount < 1 || amount > (ceiling ?? 100000))
          ? 'admin.users.gift.amountInvalid'.tr(
              namedArgs: {'max': '${ceiling ?? 100000}'},
            )
          : null;
      _reasonError = reason.length < giftReasonMinLength
          ? 'admin.users.gift.reasonShort'.tr(
              namedArgs: {'min': '$giftReasonMinLength'},
            )
          : null;
    });
    if (_amountError != null || _reasonError != null) return;

    final ok = await showConfirm(
      context,
      title: 'admin.users.gift.confirmTitle'.tr(
        namedArgs: {'amount': '$amount'},
      ),
      message: 'admin.users.gift.confirmBody'.tr(
        namedArgs: {'name': widget.recipientName},
      ),
      confirmLabel: 'admin.users.gift.send'.tr(),
    );
    if (!ok || !mounted) return;

    setState(() => _sending = true);
    try {
      await widget.send(amount!, reason);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _failure = AdminApiError.from(e).message.resolve();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: FutureBuilder<GemUsage>(
        future: _usage,
        builder: (context, snapshot) {
          final usage = snapshot.data;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'admin.users.gift.title'.tr(),
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'admin.users.gift.to'.tr(
                    namedArgs: {'name': widget.recipientName},
                  ),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
                if (usage != null)
                  Text(
                    'admin.users.gift.limit'.tr(
                      namedArgs: {
                        'max': '${usage.giftCeiling}',
                        'left': '${usage.remainingToday}',
                      },
                    ),
                    style: theme.textTheme.bodySmall,
                  )
                else if (snapshot.hasError)
                  Text(
                    'admin.users.gift.limitUnknown'.tr(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _amount,
                  label: 'admin.users.gift.amount'.tr(),
                  errorText: _amountError,
                  enabled: !_sending,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: AppSpacing.md),
                AppTextField(
                  controller: _reason,
                  label: 'admin.users.gift.reason'.tr(),
                  helper: 'admin.users.gift.reasonHint'.tr(),
                  errorText: _reasonError,
                  enabled: !_sending,
                  maxLines: 3,
                  minLines: 2,
                  maxLength: 300,
                ),
                if (_failure != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _failure!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, kMinTapTarget),
                        ),
                        onPressed: _sending
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: Text('common.cancel'.tr()),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, kMinTapTarget),
                        ),
                        onPressed: _sending ? null : () => _submit(usage),
                        child: _sending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('admin.users.gift.send'.tr()),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
