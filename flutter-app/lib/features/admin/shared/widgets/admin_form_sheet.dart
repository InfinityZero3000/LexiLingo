import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import '../../core/network/admin_api_error.dart';

/// A bottom sheet with a form: [builder] lays out the fields and [onSubmit]
/// saves them. The sheet closes with `true` once saved; a failed save keeps it
/// open with the reason, so nothing typed is lost.
Future<bool> showAdminFormSheet(
  BuildContext context, {
  required String title,
  required List<Widget> Function(BuildContext context) builder,
  required Future<void> Function() onSubmit,
  bool Function()? validate,
  String? submitLabel,
  List<TextEditingController> controllers = const [],
}) async {
  final saved = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: false,
    enableDrag: false,
    builder: (_) => _AdminFormSheet(
      title: title,
      builder: builder,
      onSubmit: onSubmit,
      validate: validate,
      submitLabel: submitLabel,
    ),
  );
  // Dispose after the exit animation; callers read the controllers right after
  // the await, so disposing any earlier would hand them dead controllers.
  Future<void>.delayed(const Duration(milliseconds: 500), () {
    for (final c in controllers) {
      c.dispose();
    }
  });
  return saved == true;
}

class _AdminFormSheet extends StatefulWidget {
  const _AdminFormSheet({
    required this.title,
    required this.builder,
    required this.onSubmit,
    this.validate,
    this.submitLabel,
  });

  final String title;
  final List<Widget> Function(BuildContext) builder;
  final Future<void> Function() onSubmit;
  final bool Function()? validate;
  final String? submitLabel;

  @override
  State<_AdminFormSheet> createState() => _AdminFormSheetState();
}

class _AdminFormSheetState extends State<_AdminFormSheet> {
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    if (widget.validate != null && !widget.validate!()) {
      setState(() => _error = 'admin.content.fillRequired'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSubmit();
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = AdminApiError.from(e).message.resolve();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.title, style: theme.textTheme.heading),
              const SizedBox(height: AppSpacing.lg),
              for (final field in widget.builder(context)) ...[
                field,
                const SizedBox(height: AppSpacing.md),
              ],
              if (_error != null) ...[
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
                const SizedBox(height: AppSpacing.md),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, kMinTapTarget),
                      ),
                      onPressed: _saving
                          ? null
                          : () => Navigator.pop(context, false),
                      child: Text('common.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, kMinTapTarget),
                      ),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(widget.submitLabel ?? 'common.save'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
