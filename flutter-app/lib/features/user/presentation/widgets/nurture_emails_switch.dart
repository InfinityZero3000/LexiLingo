import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';

class NurtureEmailsSwitch extends StatelessWidget {
  const NurtureEmailsSwitch({
    super.key,
    required this.settings,
    required this.primaryColor,
  });

  final SettingsProvider settings;
  final Color primaryColor;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text('settings.nurtureEmails'.tr()),
      subtitle: Text('settings.nurtureEmailsHint'.tr()),
      value: settings.nurtureEmailsEnabled,
      activeTrackColor: primaryColor.withValues(alpha: 0.5),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? primaryColor : null,
      ),
      onChanged: (value) async {
        final messenger = ScaffoldMessenger.of(context);
        final saved = await settings.setNurtureEmails(value);
        if (!saved && context.mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text('settings.nurtureEmailsError'.tr())),
          );
        }
      },
    );
  }
}
