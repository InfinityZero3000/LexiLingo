import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/core/di/injection_container.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/animated_ui_components.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/pages/legal_page.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

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
      );
    }
  }

  Widget _buildFlagWidget(BuildContext context, String languageCode) {
    final imageUrl = AppLocales.flagPngUrlOf(languageCode);

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: _flagWidth,
        height: _flagHeight,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fadeInDuration: Duration.zero,
          placeholder: (_, __) => _buildFlagSkeleton(context),
          errorWidget: (_, __, ___) =>
              _buildFlagFallback(context, languageCode),
        ),
      ),
    );
  }

  Widget _buildFlagSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: _flagWidth,
      height: _flagHeight,
      decoration: BoxDecoration(
        color: isDark ? AppColors.grey700 : AppColors.grey300,
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }

  Widget _buildFlagFallback(BuildContext context, String languageCode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label = AppLocales.flagCodeOf(languageCode).toUpperCase();

    return Container(
      width: _flagWidth,
      height: _flagHeight,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: isDark ? AppColors.grey800 : AppColors.grey200,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: isDark ? AppColors.textOnDarkPrimary : AppColors.textDark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();

    return Scaffold(
      appBar: AppBar(
        title: Text('settings.title'.tr()),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: settings.isLoading
          ? const Center(child: LottieLoadingWidget.medium())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                AnimatedListItem(
                  index: 0,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.language,
                    title: 'settings.language'.tr(),
                    subtitle: 'settings.language_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildLanguageSelector(context, settings),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 1,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.notifications,
                    title: 'settings.notifications'.tr(),
                    subtitle: 'settings.notifications_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildNotificationSettings(context, settings),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 2,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.volume_up,
                    title: 'settings.sound'.tr(),
                    subtitle: 'settings.sound_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildSoundSettings(context, settings),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 3,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.palette,
                    title: 'settings.theme'.tr(),
                    subtitle: 'settings.theme_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildThemeSelector(context, settings),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 4,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.person_outline,
                    title: 'settings.account'.tr(),
                    subtitle: 'settings.account_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAccountSection(context),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 5,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.people_outline_rounded,
                    title: 'settings.referral'.tr(),
                    subtitle: 'settings.referral_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildReferralSection(context),
                const SizedBox(height: 32),
                AnimatedListItem(
                  index: 6,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.info_outline,
                    title: 'settings.about'.tr(),
                    subtitle: 'settings.about_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAboutSection(context),
                const SizedBox(height: 40),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: primaryColor, size: 24),
          ),
          const SizedBox(width: 12),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: () async {
                    // Update language - this will also update the app locale
                    await settings.updateLanguage(lang['code']!, context);
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? primaryColor.withValues(alpha: 0.1)
                          : AppColors.surfaceLight.withValues(alpha: 0),
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: primaryColor, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        _buildFlagWidget(context, lang['code'] ?? 'en'),
                        const SizedBox(width: 12),
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

  Widget _buildNotificationSettings(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Enable/Disable toggle
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('settings.dailyReminder'.tr()),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('settings.reminderTime'.tr()),
                      Row(
                        children: [
                          Text(
                            settings.notificationTime,
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
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
      padding: const EdgeInsets.symmetric(vertical: 4),
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
            color: count <= 1 ? AppColors.grey400 : primaryColor,
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('settings.sound_effects'.tr()),
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
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
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: isSelected
                      ? primaryColor.withValues(alpha: 0.1)
                      : null,
                  borderRadius: BorderRadius.circular(12),
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
                    const SizedBox(height: 4),
                    Text(
                      (theme['name'] as String).tr(),
                      style: TextStyle(
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected ? primaryColor : null,
                        fontSize: 12,
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
        borderRadius: BorderRadius.circular(16),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                            style: TextStyle(
                              color: primaryColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.displayName.isNotEmpty
                              ? user.displayName
                              : user.username,
                          style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          user.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColorRoles.textMuted(isDark),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

          if (user != null) Divider(height: 1, color: AppColors.grey200),

          // Sign out button
          InkWell(
            onTap: () => _confirmSignOut(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.errorBg,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.logout,
                      color: AppColors.errorDark,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'settings.sign_out'.tr(),
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: AppColors.errorDark,
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: AppColors.grey400, size: 20),
                ],
              ),
            ),
          ),

          Divider(height: 1, color: AppColors.grey200),

          // Delete account button
          InkWell(
            onTap: () => _confirmDeleteAccount(context),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(16),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFE4E4),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.delete_forever_rounded,
                      color: Color(0xFFB91C1C),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'settings.delete_account'.tr(),
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      color: Color(0xFFB91C1C),
                    ),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: AppColors.grey400, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReferralSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.card_giftcard_rounded, color: Colors.green, size: 20),
        ),
        title: Text('settings.invite_friends'.tr(),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('settings.invite_friends_subtitle'.tr(),
            style: const TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, size: 20),
        onTap: () => _showReferralSheet(context),
      ),
    );
  }

  Future<void> _showReferralSheet(BuildContext context) async {
    final settingsProvider = context.read<SettingsProvider>();
    String? code;

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
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.grey[300], borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Icon(Icons.card_giftcard_rounded, size: 48, color: Colors.green),
              const SizedBox(height: 12),
              Text('settings.invite_title'.tr(),
                  style: Theme.of(ctx).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              Text('settings.invite_desc'.tr(),
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(color: Colors.grey),
                  textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FutureBuilder<Map<String, dynamic>>(
                future: settingsProvider.getReferralCode(),
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const CircularProgressIndicator();
                  }
                  code = snap.data!['referral_code'] as String? ?? '';
                  final total = (snap.data!['total_referrals'] as num?)?.toInt() ?? 0;
                  return Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(code ?? '',
                                style: const TextStyle(
                                  fontSize: 28, fontWeight: FontWeight.bold,
                                  letterSpacing: 4, color: Colors.green,
                                )),
                            const SizedBox(width: 12),
                            IconButton(
                              icon: const Icon(Icons.copy_rounded, color: Colors.green),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: code ?? ''));
                                ScaffoldMessenger.of(ctx).showSnackBar(
                                  SnackBar(content: Text('settings.code_copied'.tr())),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'settings.referral_count'.tr(namedArgs: {'count': total.toString()}),
                        style: const TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      FilledButton.icon(
                        icon: const Icon(Icons.share_rounded),
                        label: Text('settings.share_invite'.tr()),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.green,
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
        borderRadius: BorderRadius.circular(16),
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
                builder: (_) => const LegalPage(type: LegalPageType.privacyPolicy),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.grey200),
          _buildAboutRow(
            context,
            icon: Icons.description_outlined,
            label: 'settings.terms'.tr(),
            isDark: isDark,
            isLast: true,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const LegalPage(type: LegalPageType.termsOfService),
              ),
            ),
          ),
          Divider(height: 1, color: AppColors.grey200),
          FutureBuilder<PackageInfo>(
            future: PackageInfo.fromPlatform(),
            builder: (context, snapshot) {
              final version = snapshot.data?.version ?? '—';
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColorRoles.primary(isDark).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.info_outline,
                        color: AppColorRoles.primary(isDark),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'settings.version'.tr(namedArgs: {'version': version}),
                      style: TextStyle(
                        fontSize: 15,
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColorRoles.primary(isDark).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: AppColorRoles.primary(isDark), size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Icon(Icons.chevron_right, color: AppColors.grey400, size: 20),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('settings.delete_account'.tr()),
        content: Text('settings.delete_account_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('settings.sign_out'.tr()),
        content: Text('settings.sign_out_confirm'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('common.cancel'.tr()),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorDark,
              foregroundColor: AppColors.surfaceLight,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
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
