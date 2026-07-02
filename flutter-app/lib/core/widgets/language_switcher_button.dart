import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/services/locale_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:provider/provider.dart';

/// Compact language-switcher pill for placement in app bars and page headers.
///
/// Displays the current locale flag asset + uppercase language code (e.g. `VI`).
/// Tapping opens a BottomSheet listing all supported locales.
///
/// Works on both pre-auth and post-auth screens:
/// - Post-auth: delegates to [SettingsProvider.updateLanguage] (persists to backend + locale).
/// - Pre-auth: falls back to [LocaleService.updateAppLocale] (EasyLocalization + SharedPreferences).
class LanguageSwitcherButton extends StatelessWidget {
  const LanguageSwitcherButton({super.key});

  static void showLanguageSheet(BuildContext context) {
    final currentCode = context.locale.languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      backgroundColor: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
      builder: (sheetContext) {
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(sheetContext).size.height * 0.75,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
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
                    'settings.language'.tr(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.textDark,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: AppLocales.supportedLocales.map((locale) {
                          final code = locale.languageCode;
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
                                  ? AppColors.accentMint.withValues(
                                      alpha: isDark ? 0.08 : 0.06,
                                    )
                                  : null,
                              leading: Container(
                                width: 44,
                                height: 44,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.accentMint.withValues(
                                          alpha: isDark ? 0.2 : 0.15,
                                        )
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: _FlagImage(
                                  languageCode: code,
                                  width: 28,
                                  height: 20,
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
                        }).toList(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final code = context.locale.languageCode;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => showLanguageSheet(context),
      child: Container(
        height: 34,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isDark
              ? AppColors.accentMint.withValues(alpha: 0.12)
              : AppColors.accentMint.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _FlagImage(languageCode: code, width: 20, height: 14),
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

  static Future<void> _applyLanguage(BuildContext context, String code) async {
    // Prefer SettingsProvider when the user is authenticated (it syncs to backend).
    AuthProvider? authProvider;
    try {
      authProvider = Provider.of<AuthProvider>(context, listen: false);
    } catch (_) {
      authProvider = null;
    }

    SettingsProvider? settingsProvider;
    try {
      settingsProvider = Provider.of<SettingsProvider>(context, listen: false);
    } catch (_) {
      settingsProvider = null;
    }

    final isAuthenticated = authProvider?.isAuthenticated ?? false;
    if (isAuthenticated &&
        settingsProvider != null &&
        settingsProvider.settings != null) {
      if (!context.mounted) return;
      await settingsProvider.updateLanguage(code, context);
    } else {
      // Pre-auth: update EasyLocalization + persist to SharedPreferences directly.
      if (!context.mounted) return;
      await LocaleService.updateAppLocale(context, code);
    }
  }
}

class _FlagImage extends StatelessWidget {
  const _FlagImage({
    required this.languageCode,
    required this.width,
    required this.height,
  });

  final String languageCode;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final pngUrl = AppLocales.flagPngUrlOf(languageCode);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: width,
        height: height,
        child: CachedNetworkImage(
          imageUrl: pngUrl,
          fadeInDuration: const Duration(milliseconds: 100),
          placeholder: (context, _) => DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.accentMint.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          errorWidget: (context, _, __) {
            return Container(
              width: width,
              height: height,
              color: AppColors.accentMint.withValues(alpha: 0.18),
              alignment: Alignment.center,
              child: Icon(
                Icons.language_rounded,
                size: height,
                color: AppColors.accentMintDark,
              ),
            );
          },
          imageBuilder: (context, imageProvider) => Image(
            image: imageProvider,
            width: width,
            height: height,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}
