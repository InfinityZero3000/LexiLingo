import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';

/// Bottom-sheet shell shared by the growth edit forms: title, scrollable
/// fields, keyboard-safe padding, one primary save action.
class GrowthFormSheet extends StatelessWidget {
  const GrowthFormSheet({
    super.key,
    required this.title,
    required this.children,
    required this.onSave,
    this.saving = false,
    this.error,
  });

  final String title;
  final List<Widget> children;
  final VoidCallback onSave;
  final bool saving;

  /// Shown above the save button: a SnackBar raised from inside a modal sheet
  /// renders behind it.
  final String? error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.xl,
          AppSpacing.lg,
          AppSpacing.xl,
          MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              const SizedBox(height: AppSpacing.lg),
              ...children,
              const SizedBox(height: AppSpacing.sm),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                  child: Text(
                    error!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ),
              SizedBox(
                height: kMinTapTarget + 4,
                child: FilledButton(
                  onPressed: saving ? null : onSave,
                  child: saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text('adminGrowth.common.save'.tr()),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class GrowthField extends StatelessWidget {
  const GrowthField({
    super.key,
    required this.controller,
    required this.label,
    this.lines = 1,
    this.number = false,
    this.errorText,
  });

  final TextEditingController controller;
  final String label;
  final int lines;
  final bool number;
  final String? errorText;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: AppTextField(
      controller: controller,
      label: label,
      maxLines: lines,
      errorText: errorText,
      keyboardType: number ? TextInputType.number : null,
    ),
  );
}

class GrowthDropdown extends StatelessWidget {
  const GrowthDropdown({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
    this.optionLabel,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<String> onChanged;
  final String Function(String)? optionLabel;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
      ).applyDefaults(AppInputTheme.of(context)),
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(optionLabel?.call(o) ?? o)),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    ),
  );
}

/// Small read-only tag used on admin cards.
class GrowthChip extends StatelessWidget {
  const GrowthChip(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 1,
        vertical: AppSpacing.xs + 1,
      ),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.pillAll,
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
      ),
    );
  }
}

/// A row that says an action lives on the web admin, instead of a button for
/// something mobile deliberately does not do.
class GrowthWebOnlyNote extends StatelessWidget {
  const GrowthWebOnlyNote({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          Icon(Icons.desktop_windows_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              'adminGrowth.common.webOnlyBody'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
  }
}
