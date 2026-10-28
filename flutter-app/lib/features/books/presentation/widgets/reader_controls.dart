import 'package:easy_localization/easy_localization.dart';
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
    final accent = Theme.of(context).colorScheme.primary;
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
            'books.readerSettings'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              color: _textColor(settings.theme),
            ),
          ),
          const SizedBox(height: 20),

          // ── Font Size ──────────────────────────────
          _sectionLabel('books.fontSize'.tr(), settings.theme),
          Row(
            children: [
              IconButton(
                onPressed: settings.fontSize > 14
                    ? () => onChanged(
                        settings.copyWith(fontSize: settings.fontSize - 1),
                      )
                    : null,
                icon: const Icon(Icons.text_decrease_rounded),
                color: accent,
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: settings.fontSize,
                    min: 14,
                    max: 28,
                    divisions: 14,
                    activeColor: accent,
                    inactiveColor: accent.withValues(alpha: 0.2),
                    onChanged: (v) => onChanged(settings.copyWith(fontSize: v)),
                  ),
                ),
              ),
              IconButton(
                onPressed: settings.fontSize < 28
                    ? () => onChanged(
                        settings.copyWith(fontSize: settings.fontSize + 1),
                      )
                    : null,
                icon: const Icon(Icons.text_increase_rounded),
                color: accent,
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
          _sectionLabel('books.readerTheme'.tr(), settings.theme),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _themeChip(
                context,
                ReaderTheme.light,
                'books.themeLight'.tr(),
                AppColors.readingPaper,
                Colors.black87,
              ),
              _themeChip(
                context,
                ReaderTheme.sepia,
                'books.themeSepia'.tr(),
                AppColors.readingSepia,
                AppColors.readingSepiaText,
              ),
              _themeChip(
                context,
                ReaderTheme.dark,
                'books.themeDark'.tr(),
                AppColors.readingNight,
                Colors.white,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // ── Line Spacing ───────────────────────────
          _sectionLabel('books.lineSpacing'.tr(), settings.theme),
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 8,
                    ),
                  ),
                  child: Slider(
                    value: settings.lineSpacing,
                    min: 1.2,
                    max: 2.0,
                    divisions: 4,
                    activeColor: accent,
                    inactiveColor: accent.withValues(alpha: 0.2),
                    onChanged: (v) =>
                        onChanged(settings.copyWith(lineSpacing: v)),
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
    final accent = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: isSelected,
      child: InkWell(
        onTap: () => onChanged(settings.copyWith(theme: theme)),
        borderRadius: BorderRadius.circular(12),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          constraints: const BoxConstraints(minHeight: 44, minWidth: 72),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? accent : Colors.transparent,
              width: 2,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              fontSize: 14,
            ),
          ),
        ),
      ),
    );
  }

  Color _bgColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return AppColors.readingPaper;
      case ReaderTheme.sepia:
        return AppColors.readingSepiaAlt;
      case ReaderTheme.dark:
        return AppColors.readingNight;
    }
  }

  Color _textColor(ReaderTheme theme) {
    switch (theme) {
      case ReaderTheme.light:
        return Colors.black87;
      case ReaderTheme.sepia:
        return AppColors.readingSepiaText;
      case ReaderTheme.dark:
        return Colors.white;
    }
  }
}
