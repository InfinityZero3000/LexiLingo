import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import '../../../shared/admin_exit_scope.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_theme_toggle.dart';
import '../../../shared/widgets/open_in_web_admin_tile.dart';
import '../../auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  static const _prefSystemAlerts = 'lexi_admin_pref_system_alerts';
  static const _prefUserReports = 'lexi_admin_pref_user_reports';
  static const _prefEmailDigest = 'lexi_admin_pref_email_digest';

  bool _systemAlerts = true;
  bool _userReports = true;
  bool _emailDigest = false;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      setState(() {
        _systemAlerts = prefs.getBool(_prefSystemAlerts) ?? true;
        _userReports = prefs.getBool(_prefUserReports) ?? true;
        _emailDigest = prefs.getBool(_prefEmailDigest) ?? false;
      });
    } catch (_) {
      // Keep defaults when SharedPreferences is unavailable.
    }
  }

  Future<void> _updatePref(String key, bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, value);
    } catch (_) {
      // Ignore persistence errors in ephemeral environments.
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isSuperAdmin = auth.isSuperAdmin;

    return Scaffold(
      backgroundColor: context.ac.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: context.ac.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0.5,
            leading: MediaQuery.sizeOf(context).width >= adminWideBreakpoint
                ? null
                : IconButton(
                    icon: Icon(Icons.menu_rounded, color: context.ac.onSurface),
                    onPressed: AdminShell.openDrawer,
                  ),
            title: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: context.ac.primary,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    'L',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: context.ac.onPrimary,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    'LexiLingo',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: context.ac.onSurface,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.ac.primaryContainer,
                    borderRadius: AppRadius.smAll,
                  ),
                  child: Text(
                    'ADMIN',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.ac.primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            actions: const [AdminThemeToggleButton()],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'adminUi.settings.settings'.tr(),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.ac.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'adminUi.settings.manageYourAdministratorProfileAnd'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.ac.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Profile card
                _Card(
                  child: Column(
                    children: [
                      Container(
                        width: 84,
                        height: 84,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: context.ac.primary,
                            width: 2.5,
                          ),
                        ),
                        child: AdminUserAvatar(
                          avatarUrl: user?.avatarUrl,
                          displayName: user?.displayName ?? '',
                          radius: 38,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        user?.displayName ?? 'Admin',
                        style: Theme.of(context).textTheme.sectionTitle
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: context.ac.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: isSuperAdmin
                              ? context.ac.primary
                              : context.ac.primaryContainer,
                          borderRadius: AppRadius.smAll,
                        ),
                        child: Text(
                          (isSuperAdmin
                                  ? 'admin.shell.roleSuper'
                                  : 'admin.shell.roleAdmin')
                              .tr(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: isSuperAdmin
                                ? context.ac.onPrimary
                                : context.ac.primary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      _FormField(
                        label: 'adminUi.settings.fullName'.tr(),
                        value: user?.displayName ?? '',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _FormField(
                        label: 'adminUi.settings.emailAddress'.tr(),
                        value: user?.email ?? '',
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'adminUi.settings.syncedFromGoogle'.tr(),
                          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: context.ac.onSurfaceMuted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Appearance & Language
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.ac.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              Icons.palette_outlined,
                              color: context.ac.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'adminUi.settings.appearance'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
                      const AdminThemeModeSelector(),
                      const Divider(height: 24),
                      _LanguageSelectorRow(),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Notifications
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.ac.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              Icons.notifications_outlined,
                              color: context.ac.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'adminUi.settings.notifications'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ToggleRow(
                        title: 'adminUi.settings.systemAlerts'.tr(),
                        subtitle:
                            'adminUi.settings.criticalInfrastructureUpdates'
                                .tr(),
                        value: _systemAlerts,
                        onChanged: (v) {
                          setState(() => _systemAlerts = v);
                          _updatePref(_prefSystemAlerts, v);
                        },
                      ),
                      const Divider(height: 20),
                      _ToggleRow(
                        title: 'adminUi.settings.userReports'.tr(),
                        subtitle: 'adminUi.settings.newCurriculumFeedback'.tr(),
                        value: _userReports,
                        onChanged: (v) {
                          setState(() => _userReports = v);
                          _updatePref(_prefUserReports, v);
                        },
                      ),
                      const Divider(height: 20),
                      _ToggleRow(
                        title: 'adminUi.settings.emailDigest'.tr(),
                        subtitle: 'adminUi.settings.weeklyPerformanceAnalytics'
                            .tr(),
                        value: _emailDigest,
                        onChanged: (v) {
                          setState(() => _emailDigest = v);
                          _updatePref(_prefEmailDigest, v);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Account & System Configuration (Real Actions, Zero Mock Data)
                _Card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: context.ac.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: Icon(
                              Icons.shield_outlined,
                              color: context.ac.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'adminUi.settings.securityAccess'.tr(),
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _InfoRow(
                        icon: Icons.verified_user_outlined,
                        label: 'adminUi.settings.authMethodLabel'.tr(),
                        subtitle: 'adminUi.settings.authMethodGoogle'.tr(),
                      ),
                      const Divider(height: 20),
                      _ActionRow(
                        icon: Icons.tune_rounded,
                        label: 'admin.nav.config'.tr(),
                        subtitle: 'adminUi.settings.serverConfigHint'.tr(),
                        onTap: () => context.go('/system-settings'),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      OpenInWebAdminTile(
                        body: 'adminUi.settings.webConfigBody'.tr(),
                        path: '/admin/settings',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Switch to User Zone — only visible for whitelisted accounts
                if (auth.hasUserZoneAccess) ...[
                  _UserZoneSwitchCard(user: user),
                  const SizedBox(height: AppSpacing.lg),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: context.ac.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: context.ac.outlineVariant, width: 0.5),
      ),
      child: child,
    );
  }
}

class _FormField extends StatefulWidget {
  final String label;
  final String value;
  const _FormField({required this.label, required this.value});

  @override
  State<_FormField> createState() => _FormFieldState();
}

class _FormFieldState extends State<_FormField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.value);
  }

  @override
  void didUpdateWidget(_FormField old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) _ctrl.text = widget.value;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.6,
            color: context.ac.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _ctrl,
          readOnly: true,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: context.ac.onSurfaceVariant,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: context.ac.surfaceDim,
          ),
        ),
      ],
    );
  }
}

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.ac.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.ac.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: context.ac.primary,
        ),
      ],
    );
  }
}

class _LanguageSelectorRow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final currentCode = context.locale.languageCode;
    return Row(
      children: [
        Expanded(
          child: Text(
            'adminUi.settings.language'.tr(),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: context.ac.onSurface,
            ),
          ),
        ),
        SegmentedButton<String>(
          showSelectedIcon: false,
          segments: const [
            ButtonSegment(value: 'vi', label: Text('Tiếng Việt')),
            ButtonSegment(value: 'en', label: Text('English')),
          ],
          selected: {currentCode == 'vi' ? 'vi' : 'en'},
          onSelectionChanged: (sel) {
            final code = sel.first;
            context.setLocale(Locale(code));
          },
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: context.ac.primary),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: context.ac.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: context.ac.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ActionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _ActionRow({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: AppRadius.mdAll,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, size: 20, color: context.ac.onSurfaceVariant),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: context.ac.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.ac.onSurfaceMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: context.ac.onSurfaceMuted),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
// Switch to User Zone card + bottom sheet
// ─────────────────────────────────────────────

class _UserZoneSwitchCard extends StatelessWidget {
  final dynamic user;
  const _UserZoneSwitchCard({required this.user});

  void _show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _UserZoneSheet(user: user),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _show(context),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [context.ac.navy, context.ac.navyLight],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: context.ac.onNavy.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                color: context.ac.onNavy,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'adminUi.settings.switchToUserZone'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.ac.onNavy,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'adminUi.settings.openLexilingoAsALearner'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: context.ac.onNavy.withValues(alpha: 0.54),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: context.ac.primaryBright,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'adminUi.settings.switch'.tr(),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: context.ac.onNavy,
                  letterSpacing: 0.06,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _UserZoneSheet extends StatelessWidget {
  final dynamic user;
  const _UserZoneSheet({required this.user});

  @override
  Widget build(BuildContext context) {
    final displayName = user?.displayName as String? ?? 'Admin';
    final email = user?.email as String? ?? '';
    final isSuperAdmin = (user?.isSuperAdmin as bool?) ?? false;
    final initials = displayName.isNotEmpty
        ? displayName[0].toUpperCase()
        : 'A';

    return Container(
      decoration: BoxDecoration(
        color: context.ac.onNavy,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: AppSpacing.md),
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: context.ac.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Dark header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [context.ac.navy, context.ac.navyLight],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: context.ac.primaryContainer,
                      child: Text(
                        initials,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.ac.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: context.ac.primaryBright,
                          shape: BoxShape.circle,
                          border: Border.all(color: context.ac.navy, width: 2),
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          color: context.ac.onNavy,
                          size: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        displayName,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: context.ac.onNavy,
                        ),
                      ),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: context.ac.onNavy.withValues(alpha: 0.54),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: context.ac.primaryBright,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: context.ac.onNavy,
                                letterSpacing: 0.06,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // Body
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'adminUi.settings.yourDualAccount'.tr(),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: context.ac.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'adminUi.settings.yourAdminAccountIsLinked'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: context.ac.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Step cards
                _StepRow(
                  step: '1',
                  text: 'adminUi.settings.userZoneStep1'.tr(),
                ),
                const SizedBox(height: 10),
                _StepRow(
                  step: '2',
                  text: 'adminUi.settings.userZoneStep2'.tr(args: [email]),
                ),
                const SizedBox(height: 10),
                _StepRow(
                  step: '3',
                  text: 'adminUi.settings.userZoneStep3'.tr(),
                ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
          // Buttons
          Padding(
            padding: EdgeInsets.fromLTRB(
              20,
              0,
              20,
              MediaQuery.of(context).padding.bottom + 20,
            ),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton.icon(
                    onPressed: () {
                      final exit = AdminExitScope.maybeOf(context)?.onExit;
                      Navigator.of(context).pop();
                      exit?.call();
                    },
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      'adminUi.settings.openLearnerApp'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: context.ac.primaryBright,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    'adminUi.settings.dismiss'.tr(),
                    style: context.adminStyle(
                      color: context.ac.onSurfaceMuted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final String step;
  final String text;
  const _StepRow({required this.step, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: context.ac.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: context.ac.primary,
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.ac.onSurface),
          ),
        ),
      ],
    );
  }
}
