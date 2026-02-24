import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';
import '../../domain/entities/book_entities.dart';

/// Drawer-style panel for adjusting reader display settings.
///
/// Controls: font size (14–28), theme (Light/Sepia/Dark), line spacing.
///
/// Phase 5: Book Reading — skill: ui-ux-pro-max.
class ReaderControls extends StatelessWidget {
  final ReaderSettings settings;
  final ValueChanged<ReaderSettings> onChanged;

  const ReaderControls({
    super.key,
    required this.settings,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
      decoration: BoxDecoration(
        color: _bgColor(settings.theme),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: _textColor(settings.theme).withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          Text(
            'Reader Settings',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _textColor(settings.theme),
            ),
          ),
          const SizedBox(height: 20),

          // ── Font Size ──────────────────────────────
          _sectionLabel('Font Size', settings.theme),
          Row(
            children: [
              IconButton(
                onPressed: settings.fontSize > 14
                    ? () => onChanged(settings.copyWith(fontSize: settings.fontSize - 1))
                    : null,
                icon: const Icon(Icons.text_decrease_rounded),
                color: AppColors.primary,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: settings.fontSize,
                    min: 14,
                    max: 28,
                    divisions: 14,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.primary.withValues(alpha: 0.2),
                    onChanged: (v) => onChanged(settings.copyWith(fontSize: v)),
                  ),
                ),
              ),
              IconButton(
                onPressed: settings.fontSize < 28
                    ? () => onChanged(settings.copyWith(fontSize: settings.fontSize + 1))
                    : null,
                icon: const Icon(Icons.text_increase_rounded),
                color: AppColors.primary,
              ),
              Text(
                '${settings.fontSize.toInt()}px',
                style: TextStyle(
                  fontSize: 13,
                  color: _textColor(settings.theme).withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Theme ──────────────────────────────────
          _sectionLabel('Theme', settings.theme),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _themeChip(context, ReaderTheme.light, 'Light',
                  const Color(0xFFF8F5EE), Colors.black87),
              _themeChip(context, ReaderTheme.sepia, 'Sepia',
                  const Color(0xFFF4ECD8), const Color(0xFF4B3B2A)),
              _themeChip(context, ReaderTheme.dark, 'Dark',
                  const Color(0xFF1A1A2E), Colors.white),
            ],
          ),
          const SizedBox(height: 16),

          // ── Line Spacing ───────────────────────────
          _sectionLabel('Line Spacing', settings.theme),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  ),
                  child: Slider(
                    value: settings.lineSpacing,
                    min: 1.2,
                    max: 2.0,
                    divisions: 4,
                    activeColor: AppColors.primary,
                    inactiveColor: AppColors.primary.withValues(alpha: 0.2),
                    onChanged: (v) => onChanged(settings.copyWith(lineSpacing: v)),
                  ),
                ),
              ),
              Text(
                settings.lineSpacing.toStringAsFixed(1),
                style: TextStyle(
                  fontSize: 13,
                  color: _textColor(settings.theme).withValues(alpha: 0.7),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _sectionLabel(String label, ReaderTheme theme) => Text(
        label,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _textColor(theme).withValues(alpha: 0.6),
        ),
      );

  Widget _themeChip(
    BuildContext context,
    ReaderTheme theme,
    String label,
    Color bg,
    Color fg,
  ) {
    final isSelected = settings.theme == theme;
    return GestureDetector(
      onTap: () => onChanged(settings.copyWith(theme: theme)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: fg,
            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Color _bgColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return const Color(0xFFF8F5EE);
      case ReaderTheme.sepia:
        return const Color(0xFFEDE0CC);
      case ReaderTheme.dark:
        return const Color(0xFF1A1A2E);
    }
  }

  Color _textColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.black87;
      case ReaderTheme.sepia:
        return const Color(0xFF4B3B2A);
      case ReaderTheme.dark:
        return Colors.white;
    }
  }
}
