import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Compact language-switcher pill for placement in app bars and page headers.
///
/// Displays the current locale flag emoji + uppercase language code (e.g. `🇻🇳 VI`).
/// Tapping opens a BottomSheet listing all supported locales.
///
/// Works on both pre-auth and post-auth screens:
/// - Post-auth: delegates to [SettingsProvider.updateLanguage] (persists to backend + locale).
/// - Pre-auth: falls back to [LocaleService.updateAppLocale] (EasyLocalization + SharedPreferences).
class LanguageSwitcherButton extends StatelessWidget {
  const LanguageSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    final code = context.locale.languageCode;
    final flag = AppLocales.flagOf(code);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => _showLanguageSheet(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.accentMint.withValues(alpha: 0.12)
              : AppColors.accentMint.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: AppColors.accentMint.withValues(alpha: 0.4),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(flag, style: const TextStyle(fontSize: 14)),
            const SizedBox(width: 4),
            Text(
              code.toUpperCase(),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? AppColors.accentMint : AppColors.accentMintDark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showLanguageSheet(BuildContext context) {
    final currentCode = context.locale.languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? AppColors.grey700 : AppColors.grey300,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Choose Language',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                ...AppLocales.supportedLocales.map((locale) {
                  final code = locale.languageCode;
                  final flag = AppLocales.flagOf(code);
                  final name = AppLocales.nameOf(code);
                  final nameEn = AppLocales.nameEnOf(code);
                  final isSelected = code == currentCode;

                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      tileColor: isSelected
                          ? AppColors.accentMint
                              .withValues(alpha: isDark ? 0.08 : 0.06)
                          : null,
                      leading: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppColors.accentMint
                                  .withValues(alpha: isDark ? 0.2 : 0.15)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          flag,
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                      title: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? AppColors.accentMint
                              : isDark
                                  ? Colors.white
                                  : AppColors.textDark,
                        ),
                      ),
                      subtitle: name != nameEn
                          ? Text(
                              nameEn,
                              style: TextStyle(
                                color: isDark
                                    ? AppColors.textMuted
                                    : AppColors.textSlateLight,
                                fontSize: 12,
                              ),
                            )
                          : null,
                      trailing: isSelected
                          ? const Icon(
                              Icons.check_rounded,
                              color: AppColors.accentMint,
                            )
                          : null,
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _applyLanguage(context, code);
                      },
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _applyLanguage(BuildContext context, String code) async {
    // Prefer SettingsProvider when the user is authenticated (it syncs to backend).
    SettingsProvider? settingsProvider;
    try {
      settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    } catch (_) {
      settingsProvider = null;
    }

    if (settingsProvider != null && settingsProvider.settings != null) {
      if (!context.mounted) return;
      await settingsProvider.updateLanguage(code, context);
    } else {
      // Pre-auth: update EasyLocalization + persist to SharedPreferences directly.
      if (!context.mounted) return;
      await LocaleService.updateAppLocale(context, code);
    }
  }
}
