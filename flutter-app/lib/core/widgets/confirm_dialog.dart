import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Asks before something that cannot be undone. Resolves to false when
/// dismissed. With [requireText] the confirm button stays disabled until the
/// reader types it, and the sheet cannot be dismissed by a stray tap.
Future<bool> showConfirm(
  BuildContext context, {
  required String title,
  String? message,
  String? confirmLabel,
  String? cancelLabel,
  bool danger = false,
  String? requireText,
}) async {
  final locked = danger || requireText != null;
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    isDismissible: !locked,
    enableDrag: !locked,
    showDragHandle: !locked,
    builder: (_) => ConfirmSheet(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      requireText: requireText,
    ),
  );
  return result ?? false;
}

class ConfirmSheet extends StatefulWidget {
  const ConfirmSheet({
    super.key,
    required this.title,
    this.message,
    this.confirmLabel,
    this.cancelLabel,
    this.danger = false,
    this.requireText,
  });

  final String title;
  final String? message;
  final String? confirmLabel;
  final String? cancelLabel;
  final bool danger;
  final String? requireText;

  @override
  State<ConfirmSheet> createState() => _ConfirmSheetState();
}

class _ConfirmSheetState extends State<ConfirmSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _matches =>
      widget.requireText == null ||
      _controller.text.trim() == widget.requireText;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = widget.danger ? scheme.error : scheme.primary;
    final onAccent = widget.danger ? scheme.onError : scheme.onPrimary;

    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.sm,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.sectionTitle),
          if (widget.message != null) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              widget.message!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
          if (widget.requireText != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              'coreKit.typeToConfirm'.tr(
                namedArgs: {'text': widget.requireText!},
              ),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _controller,
              autofocus: true,
              decoration: InputDecoration(
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.mdAll,
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.xl),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                  ),
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(widget.cancelLabel ?? 'common.cancel'.tr()),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, kMinTapTarget),
                    backgroundColor: accent,
                    foregroundColor: onAccent,
                  ),
                  onPressed: _matches
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: Text(widget.confirmLabel ?? 'common.confirm'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
