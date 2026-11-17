import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/language_flag.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/animated_ui_components.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart' show AppLocales;
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/pages/legal_page.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/user/presentation/widgets/nurture_emails_switch.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Settings page for user preferences
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const double _flagWidth = 48;
  static const double _flagHeight = 32;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
    });
  }

  Future<void> _loadSettings() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      await context.read<SettingsProvider>().loadSettings(
        authProvider.currentUser!.id,
        context,
      );
    }
  }

  Widget _buildFlagWidget(BuildContext context, String languageCode) {
    return LanguageFlag(
      languageCode: languageCode,
      width: _flagWidth,
      height: _flagHeight,
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        leading: const AppBackButton(),
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: settings.isLoading
            ? const Center(child: LottieLoadingWidget.medium())
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.lg),
                children: [
                  AnimatedListItem(
                    index: 0,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.language'.tr(),
                      subtitle: 'settings.language_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildLanguageSelector(context, settings),
                  const SizedBox(height: AppSpacing.xxl),
                  if (context.watch<AuthProvider>().user != null) ...[
                    _buildSectionHeader(
                      context,
                      title: 'settings.lexiReplyLanguage'.tr(),
                      subtitle: 'settings.lexiReplyLanguage_subtitle'.tr(),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _buildLexiReplyLanguage(context),
                    const SizedBox(height: AppSpacing.xxl),
                  ],
                  AnimatedListItem(
                    index: 1,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.notifications'.tr(),
                      subtitle: 'settings.notifications_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildNotificationSettings(context, settings),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 2,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.sound'.tr(),
                      subtitle: 'settings.sound_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildSoundSettings(context, settings),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 3,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.theme'.tr(),
                      subtitle: 'settings.theme_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildThemeSelector(context, settings),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 4,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.account'.tr(),
                      subtitle: 'settings.account_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildAccountSection(context),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 5,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'offlineSync.settingsTitle'.tr(),
                      subtitle: 'offlineSync.settingsSubtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildOfflineSyncSection(context),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 6,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.referral'.tr(),
                      subtitle: 'settings.referral_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildReferralSection(context),
                  const SizedBox(height: AppSpacing.xxl),
                  AnimatedListItem(
                    index: 7,
                    duration: const Duration(milliseconds: 300),
                    delayPerItem: const Duration(milliseconds: 50),
                    child: _buildSectionHeader(
                      context,
                      title: 'settings.about'.tr(),
                      subtitle: 'settings.about_subtitle'.tr(),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  _buildAboutSection(context),
                  const SizedBox(height: 40),
                ],
              ),
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(left: AppSpacing.xs),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColorRoles.textMuted(isDark),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageSelector(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final currentLocaleCode = context.locale.languageCode;

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: SettingsProvider.availableLanguages.asMap().entries.map((
            entry,
          ) {
            final lang = entry.value;
            final isSelected = currentLocaleCode == lang['code'];
            return AnimatedListItem(
              index: entry.key,
              duration: const Duration(milliseconds: 200),
              delayPerItem: const Duration(milliseconds: 30),
              child: Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: InkWell(
                  onTap: () async {
                    // Update language - this will also update the app locale
                    await settings.updateLanguage(lang['code']!, context);
                  },
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor.withValues(alpha: 0.1)
                          : AppColors.surfaceLight.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: isSelected
                          ? Border.all(color: primaryColor, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        _buildFlagWidget(context, lang['code'] ?? 'en'),
                        const SizedBox(width: AppSpacing.md),
                        Expanded(
                          child: Text(
                            lang['name']!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? primaryColor : null,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Icon(Icons.check_circle, color: primaryColor),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildLexiReplyLanguage(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    String nameOf(String code) =>
        AppLocales.metadata[code]?['name'] ?? code.toUpperCase();
    final options = [
      (
        value: UserEntity.lexiReplyApp,
        label: 'settings.lexiReplyApp'.tr(
          namedArgs: {'language': nameOf(context.locale.languageCode)},
        ),
        icon: Icons.translate_rounded,
      ),
      (
        value: UserEntity.lexiReplyNative,
        label: 'settings.lexiReplyNative'.tr(
          namedArgs: {'language': nameOf(user.nativeLanguage)},
        ),
        icon: Icons.record_voice_over_rounded,
      ),
    ];

    Future<void> choose(String value) async {
      final messenger = ScaffoldMessenger.of(context);
      final saved = await auth.updateLexiReplyLanguage(value);
      if (!saved) {
        messenger.showSnackBar(
          SnackBar(content: Text('errors.saveFailed'.tr())),
        );
      }
    }

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            for (final option in options)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Builder(
                  builder: (context) {
                    final isSelected = user.lexiReplyLanguage == option.value;
                    return InkWell(
                      key: Key('settings-lexi-reply-${option.value}'),
                      onTap: isSelected ? null : () => choose(option.value),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: Container(
                        constraints: const BoxConstraints(minHeight: 48),
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? primaryColor.withValues(alpha: 0.1)
                              : null,
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: isSelected
                              ? Border.all(color: primaryColor, width: 2)
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              option.icon,
                              color: isSelected
                                  ? primaryColor
                                  : AppColorRoles.textMuted(isDark),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Expanded(
                              child: Text(
                                option.label,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected ? primaryColor : null,
                                ),
                              ),
                            ),
                            if (isSelected)
                              Icon(Icons.check_circle, color: primaryColor),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationSettings(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          children: [
            // Enable/Disable toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(
                  child: Text(
                    'settings.dailyReminder'.tr(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Switch(
                  value: settings.notificationEnabled,
                  onChanged: (value) =>
                      settings.updateNotificationSettings(enabled: value),
                  activeTrackColor: primaryColor.withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return primaryColor;
                    }
                    return null;
                  }),
                ),
              ],
            ),
            if (settings.notificationEnabled) ...[
              const Divider(),
              InkWell(
                onTap: () async {
                  final time = await showTimePicker(
                    context: context,
                    initialTime: TimeOfDay(
                      hour: int.parse(settings.notificationTime.split(':')[0]),
                      minute: int.parse(
                        settings.notificationTime.split(':')[1],
                      ),
                    ),
                  );
                  if (time != null) {
                    final formatted =
                        '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    settings.updateNotificationSettings(time: formatted);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text(
                          'settings.reminderTime'.tr(),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Row(
                        children: [
                          Text(
                            settings.notificationTime,
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.grey500,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(),
              _buildSwitchRow(
                context,
                label: 'settings.pushReminder'.tr(),
                value: settings.pushReminderEnabled,
                onChanged: (value) =>
                    settings.updateReminderChannels(pushEnabled: value),
                primaryColor: primaryColor,
              ),
              _buildSwitchRow(
                context,
                label: 'settings.emailReminder'.tr(),
                value: settings.emailReminderEnabled,
                onChanged: (value) =>
                    settings.updateReminderChannels(emailEnabled: value),
                primaryColor: primaryColor,
              ),
              if (settings.emailReminderEnabled)
                _buildCadenceRow(context, settings, primaryColor),
              _buildMinDueCountRow(context, settings, primaryColor),
            ],
            const Divider(),
            NurtureEmailsSwitch(settings: settings, primaryColor: primaryColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchRow(
    BuildContext context, {
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color primaryColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeTrackColor: primaryColor.withValues(alpha: 0.5),
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.selected)) {
                return primaryColor;
              }
              return null;
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildCadenceRow(
    BuildContext context,
    SettingsProvider settings,
    Color primaryColor,
  ) {
    final options = <int, String>{
      3: 'settings.emailCadenceEvery3Days'.tr(),
      7: 'settings.emailCadenceWeekly'.tr(),
      14: 'settings.emailCadenceEvery2Weeks'.tr(),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'settings.emailCadence'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          DropdownButton<int>(
            value: options.containsKey(settings.emailCadenceDays)
                ? settings.emailCadenceDays
                : 7,
            underline: const SizedBox.shrink(),
            items: options.entries
                .map(
                  (entry) => DropdownMenuItem<int>(
                    value: entry.key,
                    child: Text(entry.value),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value == null) return;
              settings.updateReminderChannels(emailCadenceDays: value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMinDueCountRow(
    BuildContext context,
    SettingsProvider settings,
    Color primaryColor,
  ) {
    final count = settings.reminderMinDueCount;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'settings.minDueCount'.tr(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            color: count <= 1
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : primaryColor,

            onPressed: count <= 1
                ? null
                : () => settings.updateReminderChannels(minDueCount: count - 1),
          ),
          SizedBox(
            width: 36,
            child: Text(
              '$count',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: primaryColor,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            color: primaryColor,
            onPressed: count >= 20
                ? null
                : () => settings.updateReminderChannels(minDueCount: count + 1),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundSettings(BuildContext context, SettingsProvider settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: Text(
                'settings.sound_effects'.tr(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Switch(
              value: settings.soundEnabled,
              onChanged: settings.updateSoundEnabled,
              activeTrackColor: primaryColor.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return primaryColor;
                }
                return null;
              }),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeSelector(BuildContext context, SettingsProvider settings) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final themes = [
      {
        'code': 'light',
        'name': 'settings.theme_light',
        'icon': Icons.light_mode,
      },
      {'code': 'dark', 'name': 'settings.theme_dark', 'icon': Icons.dark_mode},
      {
        'code': 'system',
        'name': 'settings.theme_system',
        'icon': Icons.settings_suggest,
      },
    ];

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: themes.map((theme) {
            final isSelected = settings.theme == theme['code'];
            final themeCode = theme['code'] as String;

            return InkWell(
              key: Key('settings-theme-$themeCode'),
              onTap: () async {
                if (isSelected) return;
                await settings.updateTheme(themeCode);
              },
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: AppSpacing.md,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.1)
                      : null,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: isSelected
                      ? Border.all(color: primaryColor, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      theme['icon'] as IconData,
                      color: isSelected
                          ? primaryColor
                          : AppColorRoles.textMuted(isDark),
                      size: 28,
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      (theme['name'] as String).tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? primaryColor : null,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildAccountSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.currentUser;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // User info row
          if (user != null)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: primaryColor.withValues(alpha: 0.15),
                    child: ClipOval(
                      child: NetworkAvatarImage(
                        imageUrl: user.avatarUrl,
                        fit: BoxFit.cover,
                        width: 44,
                        height: 44,
                        fallback: Center(
                          child: Text(
                            (user.displayName.isNotEmpty
                                    ? user.displayName[0]
                                    : user.email[0])
                                .toUpperCase(),
                            style: Theme.of(context).textTheme.sectionTitle
                                ?.copyWith(
                                  color: primaryColor,
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : user.username,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColorRoles.textMuted(isDark),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (user != null)
            Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant,
            ),

          // Sign out button
          InkWell(
            onTap: () => _confirmSignOut(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(
                      Icons.logout,
                      color: Theme.of(context).colorScheme.error,

                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    'settings.sign_out'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),

          // Delete account button
          InkWell(
            onTap: () => _confirmDeleteAccount(context),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.lg,
                vertical: 14,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(AppSpacing.sm),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: AppColors.errorDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Flexible(
                    child: Text(
                      'settings.delete_account'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w500,
                        color: AppColors.errorDark,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineSyncSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => Navigator.pushNamed(context, '/offline-sync'),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: 14,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(
                  Icons.cloud_done_outlined,
                  color: primaryColor,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'offlineSync.title'.tr(),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'offlineSync.entrySubtitle'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReferralSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: isDark
              ? AppColors.onGradient.withValues(alpha: 0.08)
              : Theme.of(context).colorScheme.shadow.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: AppSpacing.xs,
        ),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: context.status.success.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Icon(
            Icons.card_giftcard_rounded,
            color: context.status.success,
            size: 20,
          ),
        ),
        title: Text(
          'settings.invite_friends'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          'settings.invite_friends_subtitle'.tr(),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showReferralSheet(context),
      ),
    );
  }

  Future<void> _showReferralSheet(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    String? code;
    var referralFuture = settingsProvider.getReferralCode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Icon(
                Icons.card_giftcard_rounded,
                size: 48,
                color: context.status.success,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'settings.invite_title'.tr(),
                style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                'settings.invite_desc'.tr(),
                style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),

                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AppSpacing.xl),
              FutureBuilder<Map<String, dynamic>>(
                future: referralFuture,
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const CircularProgressIndicator();
                  }
                  if (snap.hasError || !snap.hasData) {
                    return Column(
                      children: [
                        Text(
                          'notifications.somethingWentWrong'.tr(),
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: AppSpacing.md),
                        OutlinedButton(
                          child: Text('home.reload'.tr()),
                          onPressed: () => setSheetState(() {
                            referralFuture = settingsProvider.getReferralCode();
                          }),
                        ),
                      ],
                    );
                  }
                  code = snap.data!['referral_code'] as String? ?? '';
                  final total =
                      (snap.data!['total_referrals'] as num?)?.toInt() ?? 0;
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: context.status.success.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(
                            color: context.status.success.withValues(
                              alpha: 0.3,
                            ),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              code ?? '',
                              style: Theme.of(context).textTheme.headlineMedium
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 4,
                                    color: context.status.success,
                                  ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            IconButton(
                              icon: Icon(
                                Icons.copy_rounded,
                                color: context.status.success,
                              ),
                              onPressed: () {
                                Clipboard.setData(
                                  ClipboardData(text: code ?? ''),
                                );
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(
                                    content: Text('settings.code_copied'.tr()),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        'settings.referral_count'.tr(
                          namedArgs: {'count': total.toString()},
                        ),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.share_rounded),
                        label: Text('settings.share_invite'.tr()),
                        style: FilledButton.styleFrom(
                          backgroundColor: context.status.success,

                          minimumSize: const Size(double.infinity, 48),
                        ),
                        onPressed: () {
                          Share.share(
                            '${'settings.invite_message'.tr()}\n\n'
                            'https://lexilingo.app/referral/$code',
                          );
                        },
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildAboutRow(
            context,
            icon: Icons.privacy_tip_outlined,
            label: 'settings.privacy'.tr(),
            isDark: isDark,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const LegalPage(type: LegalPageType.privacyPolicy),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),

          _buildAboutRow(
            context,
            icon: Icons.description_outlined,
            label: 'settings.terms'.tr(),
            isDark: isDark,
            isLast: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) =>
                    const LegalPage(type: LegalPageType.termsOfService),
              ),
            ),
          ),
          Divider(
            height: 1,
            color: Theme.of(context).colorScheme.outlineVariant,
          ),

          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '—';
              return Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.lg,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      decoration: BoxDecoration(
                        color: AppColorRoles.primary(
                          isDark,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: AppColorRoles.primary(isDark),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      'settings.version'.tr(namedArgs: {'version': version}),
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: AppColorRoles.textMuted(isDark),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAboutRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    required bool isDark,
    bool isLast = false,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: isLast
          ? const BorderRadius.vertical(bottom: Radius.circular(16))
          : BorderRadius.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: 14,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColorRoles.primary(isDark).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(icon, color: AppColorRoles.primary(isDark), size: 20),
            ),
            const SizedBox(width: AppSpacing.md),
            Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(
              Icons.chevron_right,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('settings.delete_account'.tr()),
        content: Text('settings.delete_account_confirm'.tr()),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.errorDark,
              foregroundColor: AppColors.onGradient,

              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('settings.delete_account_confirm_btn'.tr()),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    try {
      await context.read<AuthProvider>().deleteAccount();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('settings.delete_account_error'.tr())),
        );
      }
    }
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        title: Text('settings.sign_out'.tr()),
        content: Text('settings.sign_out_confirm'.tr()),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,

              foregroundColor: AppColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('settings.sign_out'.tr()),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await context.read<AuthProvider>().signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }
}
