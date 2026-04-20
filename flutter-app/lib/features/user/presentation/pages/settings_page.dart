import 'package:easy_localization/easy_localization.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/theme_ripple_overlay.dart';
import 'package:lexilingo_app/core/widgets/animated_ui_components.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:lexilingo_app/core/theme/theme_ripple_bus.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

/// Settings page for user preferences
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _flagsReady = false;

  static const Map<String, String> _flagImageByLanguage = {
    'vi': 'https://flagcdn.com/w80/vn.png',
    'en': 'https://flagcdn.com/w80/us.png',
    'ja': 'https://flagcdn.com/w80/jp.png',
    'ko': 'https://flagcdn.com/w80/kr.png',
  };

  static const Map<String, String> _flagLabelByLanguage = {
    'vi': 'VN',
    'en': 'US',
    'ja': 'JP',
    'ko': 'KR',
  };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSettings();
      _precacheFlagImages(context);
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

  Future<void> _precacheFlagImages(BuildContext context) async {
    for (final imageUrl in _flagImageByLanguage.values) {
      try {
        await precacheImage(CachedNetworkImageProvider(imageUrl), context);
      } catch (_) {
        // Ignore preload failures; each row has its own fallback.
      }
    }

    if (!mounted) return;
    setState(() => _flagsReady = true);
  }

  Widget _buildFlagWidget(BuildContext context, String languageCode) {
    final imageUrl = _flagImageByLanguage[languageCode];
    if (imageUrl == null) {
      return _buildFlagFallback(context, languageCode);
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 28,
        height: 20,
        child: CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          fadeInDuration: const Duration(milliseconds: 120),
          placeholder: (context, url) => _buildFlagSkeleton(context),
          errorWidget: (context, url, error) =>
              _buildFlagFallback(context, languageCode),
        ),
      ),
    );
  }

  Widget _buildFlagSkeleton(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(color: isDark ? AppColors.grey700 : AppColors.grey300);
  }

  Widget _buildFlagFallback(BuildContext context, String languageCode) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final label =
        _flagLabelByLanguage[languageCode] ?? languageCode.toUpperCase();

    return Container(
      width: 28,
      height: 20,
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
          color: isDark ? AppColors.surfaceLight : AppColors.textDark,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ThemeRippleOverlay(
      child: Scaffold(
        appBar: AppBar(
          title: Text('settings.title'.tr()),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Consumer<SettingsProvider>(
          builder: (context, settings, child) {
            if (settings.isLoading) {
              return const Center(child: LottieLoadingWidget.medium());
            }

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Daily Goal Section
                AnimatedListItem(
                  index: 0,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.flag,
                    title: 'settings.daily_goal'.tr(),
                    subtitle: 'settings.daily_goal_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildDailyGoalSelector(context, settings),

                const SizedBox(height: 32),

                // Language Section
                AnimatedListItem(
                  index: 1,
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

                // Notifications Section
                AnimatedListItem(
                  index: 2,
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

                // Sound Section
                AnimatedListItem(
                  index: 3,
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

                // Theme Section
                AnimatedListItem(
                  index: 4,
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

                // Account Section
                AnimatedListItem(
                  index: 5,
                  duration: const Duration(milliseconds: 300),
                  delayPerItem: const Duration(milliseconds: 50),
                  child: _buildSectionHeader(
                    context,
                    icon: Icons.manage_accounts,
                    title: 'settings.account'.tr(),
                    subtitle: 'settings.account_subtitle'.tr(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildAccountSection(context),

                const SizedBox(height: 40),
              ],
            );
          },
        ),
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

  Widget _buildDailyGoalSelector(
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
            // Current goal display
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [primaryColor, primaryColor.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    settings.currentGoalIcon,
                    size: 32,
                    color: Theme.of(context).colorScheme.surface,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Text(
                        '${settings.dailyGoalXP} XP',
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.surface,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        settings.currentGoalLabel,
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.surface.withValues(alpha: 0.9),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Goal options
            ...SettingsProvider.dailyGoalPresets.map((goal) {
              final isSelected = settings.dailyGoalXP == goal['xp'];
              return AnimatedListItem(
                index: SettingsProvider.dailyGoalPresets.indexOf(goal),
                duration: const Duration(milliseconds: 200),
                delayPerItem: const Duration(milliseconds: 30),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: InkWell(
                    onTap: () => settings.updateDailyGoal(goal['xp'] as int),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? primaryColor.withValues(alpha: 0.1)
                            : (isDark
                                  ? AppColors.surfaceDarkMuted.withValues(
                                      alpha: 0.5,
                                    )
                                  : AppColors.grey100),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? primaryColor : AppColors.grey300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            goal['icon'] as IconData,
                            size: 24,
                            color: isSelected
                                ? primaryColor
                                : AppColorRoles.textMuted(isDark),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  goal['label'] as String,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: isSelected ? primaryColor : null,
                                  ),
                                ),
                                Text(
                                  goal['description'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: AppColorRoles.textMuted(isDark),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${goal['xp']} XP',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? primaryColor
                                  : AppColorRoles.textSecondary(isDark),
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            Icon(Icons.check_circle, color: primaryColor),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageSelector(
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
          children: SettingsProvider.availableLanguages.map((lang) {
            final isSelected = settings.language == lang['code'];
            return AnimatedListItem(
              index: SettingsProvider.availableLanguages.indexOf(lang),
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
                        _flagsReady
                            ? _buildFlagWidget(context, lang['code'] ?? 'en')
                            : _buildFlagSkeleton(context),
                        const SizedBox(width: 12),
                        Text(
                          lang['name']!,
                          style: TextStyle(
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected ? primaryColor : null,
                          ),
                        ),
                        const Spacer(),
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
              // Reminder time
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
            ],
          ],
        ),
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
            Offset? tapOrigin;

            return InkWell(
              onTapDown: (details) {
                tapOrigin = details.globalPosition;
              },
              onTap: () {
                if (isSelected) return;

                final themeCode = theme['code'] as String;
                final origin = tapOrigin ?? _screenCenter(context);

                ThemeRippleBus.instance.emit(
                  origin: origin,
                  themeCode: themeCode,
                );

                settings.updateTheme(themeCode);
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

  Offset _screenCenter(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Offset(size.width / 2, size.height / 2);
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
            color: AppColors.textDark.withValues(alpha: 0.05),
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
        ],
      ),
    );
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
