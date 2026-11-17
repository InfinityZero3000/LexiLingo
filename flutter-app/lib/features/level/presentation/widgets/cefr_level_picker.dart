import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// One CEFR level as the learner is asked about it — at onboarding and when
/// they change it from their profile. One list, so both ask the same question.
class CefrLevelOption {
  final String code;
  final String labelKey;
  final IconData icon;

  const CefrLevelOption(this.code, this.labelKey, this.icon);
}

const cefrLevelOptions = <CefrLevelOption>[
  CefrLevelOption('A1', 'onboarding.levelA1', Icons.child_care_rounded),
  CefrLevelOption('A2', 'onboarding.levelA2', Icons.directions_walk_rounded),
  CefrLevelOption('B1', 'onboarding.levelB1', Icons.directions_run_rounded),
  CefrLevelOption('B2', 'onboarding.levelB2', Icons.directions_bike_rounded),
  CefrLevelOption('C1', 'onboarding.levelC1', Icons.workspace_premium_rounded),
  CefrLevelOption('C2', 'onboarding.levelC2', Icons.emoji_events_rounded),
];

int cefrIndex(String level) =>
    cefrLevelOptions.indexWhere((o) => o.code == level.toUpperCase());

/// The level list for the profile. Marks the certified level, and says which
/// choices sit above it (they will show as unverified until the level exam).
class CefrLevelPicker extends StatelessWidget {
  final String value;
  final String certifiedLevel;
  final ValueChanged<String> onChanged;

  const CefrLevelPicker({
    super.key,
    required this.value,
    required this.certifiedLevel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final certified = cefrIndex(certifiedLevel);

    return RadioGroup<String>(
      groupValue: value,
      onChanged: (code) {
        if (code != null) onChanged(code);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (index, option) in cefrLevelOptions.indexed)
            RadioListTile<String>(
              value: option.code,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
              ),
              secondary: Icon(option.icon, color: scheme.primary),
              title: Text(option.labelKey.tr()),
              subtitle: index == certified
                  ? Text('profile.levelCertifiedTag'.tr())
                  : index > certified
                  ? Text(
                      'profile.levelUnverifiedTag'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    )
                  : null,
            ),
        ],
      ),
    );
  }
}
