import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/animated_ui_components.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

/// Settings page for user preferences
/// Implements Task 4.5.2: Language preferences
/// Implements Task 4.5.3: Daily goal setting
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          if (settings.isLoading) {
            return const Center(child: CircularProgressIndicator());
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
                  title: 'Daily Goal',
                  subtitle: 'Set your daily XP target',
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
                  title: 'App Language',
                  subtitle: 'Choose your preferred language',
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
                  title: 'Notifications',
                  subtitle: 'Manage your reminders',
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
                  title: 'Sound',
                  subtitle: 'Audio settings',
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
                  title: 'Theme',
                  subtitle: 'Customize appearance',
                ),
              ),
              const SizedBox(height: 12),
              _buildThemeSelector(context, settings),

              const SizedBox(height: 40),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: AppColors.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
          ],
        ),
      ],
    );
  }

  /// Daily Goal Selector - Task 4.5.3
  Widget _buildDailyGoalSelector(BuildContext context, SettingsProvider settings) {
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
                  colors: [AppColors.primary, AppColors.primary.withValues(alpha: 0.7)],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    settings.currentGoalIcon,
                    size: 32,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    children: [
                      Text(
                        '${settings.dailyGoalXP} XP',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        settings.currentGoalLabel,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.9),
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
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppColors.primary.withValues(alpha: 0.1)
                            : Colors.grey.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected ? AppColors.primary : Colors.grey.shade300,
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            goal['icon'] as IconData,
                            size: 24,
                            color: isSelected ? AppColors.primary : Colors.grey[600],
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
                                    color: isSelected ? AppColors.primary : null,
                                  ),
                                ),
                                Text(
                                  goal['description'] as String,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '${goal['xp']} XP',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: isSelected ? AppColors.primary : Colors.grey[700],
                            ),
                          ),
                          if (isSelected) ...[
                            const SizedBox(width: 8),
                            const Icon(Icons.check_circle, color: AppColors.primary),
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

  /// Language Selector - Task 4.5.2
  Widget _buildLanguageSelector(BuildContext context, SettingsProvider settings) {
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
                  onTap: () => settings.updateLanguage(lang['code']!),
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppColors.primary.withValues(alpha: 0.1)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(10),
                      border: isSelected
                          ? Border.all(color: AppColors.primary, width: 2)
                          : null,
                    ),
                    child: Row(
                      children: [
                        Text(lang['flag']!, style: const TextStyle(fontSize: 24)),
                        const SizedBox(width: 12),
                        Text(
                          lang['name']!,
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? AppColors.primary : null,
                          ),
                        ),
                        const Spacer(),
                        if (isSelected)
                          const Icon(Icons.check_circle, color: AppColors.primary),
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

  Widget _buildNotificationSettings(BuildContext context, SettingsProvider settings) {
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
                const Text('Daily Reminders'),
                Switch(
                  value: settings.notificationEnabled,
                  onChanged: (value) => settings.updateNotificationSettings(enabled: value),
                  activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
                  thumbColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.selected)) {
                      return AppColors.primary;
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
                      minute: int.parse(settings.notificationTime.split(':')[1]),
                    ),
                  );
                  if (time != null) {
                    final formatted = '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
                    settings.updateNotificationSettings(time: formatted);
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Reminder Time'),
                      Row(
                        children: [
                          Text(
                            settings.notificationTime,
                            style: const TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.chevron_right, color: Colors.grey),
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
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Row(
              children: [
                Icon(Icons.volume_up, color: AppColors.primary),
                SizedBox(width: 12),
                Text('Sound Effects'),
              ],
            ),
            Switch(
              value: settings.soundEnabled,
              onChanged: settings.updateSoundEnabled,
              activeTrackColor: AppColors.primary.withValues(alpha: 0.5),
              thumbColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return AppColors.primary;
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
    final themes = [
      {'code': 'light', 'name': 'Light', 'icon': Icons.light_mode},
      {'code': 'dark', 'name': 'Dark', 'icon': Icons.dark_mode},
      {'code': 'system', 'name': 'System', 'icon': Icons.settings_suggest},
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
            return InkWell(
              onTap: () => settings.updateTheme(theme['code'] as String),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.primary.withValues(alpha: 0.1) : null,
                  borderRadius: BorderRadius.circular(12),
                  border: isSelected
                      ? Border.all(color: AppColors.primary, width: 2)
                      : null,
                ),
                child: Column(
                  children: [
                    Icon(
                      theme['icon'] as IconData,
                      color: isSelected ? AppColors.primary : Colors.grey,
                      size: 28,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      theme['name'] as String,
                      style: TextStyle(
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? AppColors.primary : null,
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
}
