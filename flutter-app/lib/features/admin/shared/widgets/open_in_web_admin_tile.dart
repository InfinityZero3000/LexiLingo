import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:url_launcher/url_launcher.dart';

/// Where the web admin lives. Actions the phone app deliberately leaves out
/// (deleting accounts, role changes, wallet and premium corrections, bulk work)
/// point here.
const adminWebUrl = 'https://admin.lexilingo.me';

/// A note that [body] is done on the web admin, with a button to open it.
class OpenInWebAdminTile extends StatelessWidget {
  const OpenInWebAdminTile({
    super.key,
    required this.body,
    this.path = '',
    this.launch,
  });

  final String body;

  /// Path under [adminWebUrl], e.g. `/admin/users`.
  final String path;

  /// Replaces the real launcher in tests.
  final Future<bool> Function(Uri uri)? launch;

  Future<void> _open() async {
    final uri = Uri.parse('$adminWebUrl$path');
    await (launch ?? (u) => launchUrl(u, mode: LaunchMode.externalApplication))(
      uri,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: AppRadius.lgAll,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.desktop_windows_outlined, color: scheme.onSurfaceVariant),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'admin.webOnly.title'.tr(),
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  body,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: _open,
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: Text('admin.webOnly.open'.tr()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
