import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class FilterOption<T> {
  const FilterOption({required this.value, required this.label, this.icon});

  final T value;
  final String label;
  final IconData? icon;
}

/// Horizontal chips, one selected. Tapping the selected chip clears it when
/// [allowClear] is set.
class FilterChipBar<T> extends StatelessWidget {
  const FilterChipBar({
    super.key,
    required this.options,
    required this.selected,
    required this.onSelected,
    this.allowClear = false,
    this.padding = const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
  });

  final List<FilterOption<T>> options;
  final T? selected;
  final ValueChanged<T?> onSelected;
  final bool allowClear;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(
        children: [
          for (final option in options) ...[
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: kMinTapTarget),
              child: Center(
                child: ChoiceChip(
                  materialTapTargetSize: MaterialTapTargetSize.padded,
                  avatar: option.icon == null
                      ? null
                      : Icon(option.icon, size: 18),
                  label: Text(option.label),
                  selected: option.value == selected,
                  showCheckmark: true,
                  onSelected: (isOn) => onSelected(
                    isOn ? option.value : (allowClear ? null : option.value),
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}

/// Segmented control: a grey track with a raised thumb on the active segment.
class SegmentedTabs<T> extends StatelessWidget {
  const SegmentedTabs({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<FilterOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.mdAll,
      ),
      child: Row(
        children: [
          for (final option in options)
            Expanded(
              child: Semantics(
                button: true,
                selected: option.value == selected,
                child: InkWell(
                  borderRadius: AppRadius.smAll,
                  onTap: () => onChanged(option.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    constraints: const BoxConstraints(
                      minHeight: kMinTapTarget - AppSpacing.sm,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    decoration: BoxDecoration(
                      color: option.value == selected
                          ? scheme.surface
                          : Colors.transparent,
                      borderRadius: AppRadius.smAll,
                    ),
                    child: Text(
                      option.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: option.value == selected
                            ? scheme.onSurface
                            : scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
