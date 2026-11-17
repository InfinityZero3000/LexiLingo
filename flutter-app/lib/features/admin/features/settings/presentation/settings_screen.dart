import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _systemAlerts = true;
  bool _userReports = true;
  bool _emailDigest = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final user = auth.user;
    final isSuperAdmin = auth.isSuperAdmin;
    final hasAvatar = user?.avatarUrl?.trim().isNotEmpty == true;

    return Scaffold(
      backgroundColor: AdminColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AdminColors.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(
                Icons.menu_rounded,
                color: AdminColors.onSurface,
              ),
              onPressed: AdminShell.openDrawer,
            ),
            title: Row(
              children: [
                const Icon(
                  Icons.language,
                  color: AdminColors.primary,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Text(
                  'LingoAdmin',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AdminColors.primary,
                  ),
                ),
              ],
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'Settings',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AdminColors.onSurface,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Manage your administrator profile and platform configuration.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AdminColors.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),

                // Profile card
                _Card(
                  child: Column(
                    children: [
                      SizedBox(
                        width: 88,
                        height: 88,
                        child: Stack(
                          children: [
                            Container(
                              width: 80,
                              height: 80,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: AdminColors.primary,
                                  width: 2.5,
                                ),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: AdminColors.primaryContainer,
                                backgroundImage: hasAvatar
                                    ? NetworkImage(user!.avatarUrl!.trim())
                                    : null,
                                // Initial is always the child so it still shows
                                // if the network avatar fails to load —
                                // onBackgroundImageError only silences the
                                // exception, it can't swap in a fallback.
                                onBackgroundImageError: hasAvatar
                                    ? (_, __) {}
                                    : null,
                                child: Text(
                                  user?.displayName.isNotEmpty == true
                                      ? user!.displayName[0].toUpperCase()
                                      : 'A',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        color: AdminColors.primary,
                                      ),
                                ),
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AdminColors.primaryBright,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.onPrimary,
                                    width: 2,
                                  ),
                                ),
                                child: Icon(
                                  Icons.camera_alt,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  size: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        user?.displayName ?? 'Admin User',
                        style: Theme.of(context).textTheme.sectionTitle
                            ?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: AdminColors.onSurface,
                            ),
                      ),
                      Text(
                        isSuperAdmin
                            ? 'Super Administrator'
                            : 'Senior Curriculum Director',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AdminColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 20),
                      _FormField(
                        label: 'FULL NAME',
                        value: user?.displayName ?? '',
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _FormField(
                        label: 'EMAIL ADDRESS',
                        value: user?.email ?? '',
                      ),
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
                              color: AdminColors.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: const Icon(
                              Icons.notifications_outlined,
                              color: AdminColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'Notifications',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _ToggleRow(
                        title: 'System Alerts',
                        subtitle: 'Critical infrastructure updates',
                        value: _systemAlerts,
                        onChanged: (v) => setState(() => _systemAlerts = v),
                      ),
                      const Divider(height: 20),
                      _ToggleRow(
                        title: 'User Reports',
                        subtitle: 'New curriculum feedback',
                        value: _userReports,
                        onChanged: (v) => setState(() => _userReports = v),
                      ),
                      const Divider(height: 20),
                      _ToggleRow(
                        title: 'Email Digest',
                        subtitle: 'Weekly performance analytics',
                        value: _emailDigest,
                        onChanged: (v) => setState(() => _emailDigest = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // Security
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
                              color: AdminColors.primaryContainer,
                              borderRadius: BorderRadius.circular(AppRadius.md),
                            ),
                            child: const Icon(
                              Icons.shield_outlined,
                              color: AdminColors.primary,
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Text(
                            'Security & Access',
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      _SecurityRow(
                        label: 'Change Password',
                        subtitle: 'Last updated 32 days ago',
                        icon: Icons.password_outlined,
                      ),
                      const Divider(height: 16),
                      _SecurityRow(
                        label: 'Two-Factor Auth',
                        subtitle: 'Authenticator app enabled',
                        icon: Icons.security_outlined,
                      ),
                      const Divider(height: 16),
                      Text(
                        'ACTIVE SESSIONS',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08,
                          color: AdminColors.onSurfaceMuted,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _SessionRow(
                        device: 'MacBook Pro - San Francisco, USA',
                        subtitle: 'Current Session',
                        isCurrent: true,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SessionRow(
                        device: 'iPhone 15 - San Francisco, USA',
                        subtitle: 'Active 2 hours ago',
                        isCurrent: false,
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
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
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
            letterSpacing: 0.08,
            color: AdminColors.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextField(
          controller: _ctrl,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: const InputDecoration(isDense: true),
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
                  color: AdminColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AdminColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AdminColors.primary,
        ),
      ],
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;

  const _SecurityRow({
    required this.label,
    required this.subtitle,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AdminColors.onSurfaceVariant),
        const SizedBox(width: AppSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AdminColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AdminColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AdminColors.onSurfaceMuted),
      ],
    );
  }
}

class _SessionRow extends StatelessWidget {
  final String device;
  final String subtitle;
  final bool isCurrent;

  const _SessionRow({
    required this.device,
    required this.subtitle,
    required this.isCurrent,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          isCurrent ? Icons.laptop_mac_outlined : Icons.smartphone_outlined,
          size: 18,
          color: AdminColors.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                device,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: AdminColors.onSurface,
                ),
              ),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AdminColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
        ),
      ],
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
          gradient: const LinearGradient(
            colors: [AdminColors.navy, AdminColors.navyLight],
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
                color: Theme.of(
                  context,
                ).colorScheme.onPrimary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Icon(
                Icons.swap_horiz_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Switch to User Zone',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Open LexiLingo as a learner',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.54),
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AdminColors.primaryBright,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                'SWITCH',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(context).colorScheme.onPrimary,
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
        color: Theme.of(context).colorScheme.onPrimary,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
                color: AdminColors.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Dark header
          Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [AdminColors.navy, AdminColors.navyLight],
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
                      backgroundColor: AdminColors.primaryContainer,
                      child: Text(
                        initials,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: AdminColors.primary,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AdminColors.primaryBright,
                          shape: BoxShape.circle,
                          border: Border.all(color: AdminColors.navy, width: 2),
                        ),
                        child: Icon(
                          Icons.school_outlined,
                          color: Theme.of(context).colorScheme.onPrimary,
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
                          color: Theme.of(context).colorScheme.onPrimary,
                        ),
                      ),
                      Text(
                        email,
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimary.withValues(alpha: 0.54),
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
                          color: AdminColors.primaryBright,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onPrimary,
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
                  'Your dual account',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AdminColors.onSurface,
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  'Your admin account is linked to a LexiLingo learner profile with the same email. '
                  'Open the LexiLingo app on your device to continue as a learner — '
                  'you\'ll be logged in automatically if you use the same email.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AdminColors.onSurfaceVariant,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 20),
                // Step cards
                _StepRow(
                  step: '1',
                  text: 'Open the LexiLingo app on your device',
                ),
                const SizedBox(height: 10),
                _StepRow(step: '2', text: 'Sign in with $email'),
                const SizedBox(height: 10),
                _StepRow(
                  step: '3',
                  text: 'Your learner progress and data will be ready',
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
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(
                      'Open LexiLingo App',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminColors.primaryBright,
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
                    'Dismiss',
                    style: GoogleFonts.spaceGrotesk(
                      color: AdminColors.onSurfaceMuted,
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
            color: AdminColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              step,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w700,
                color: AdminColors.primary,
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
            ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurface),
          ),
        ),
      ],
    );
  }
}
