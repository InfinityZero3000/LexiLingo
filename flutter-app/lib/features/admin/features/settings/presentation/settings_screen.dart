import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../auth/presentation/auth_provider.dart';

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

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
              onPressed: AdminShell.openDrawer,
            ),
            title: Row(
              children: [
                const Icon(Icons.language, color: AppColors.primary, size: 22),
                const SizedBox(width: 6),
                Text('LingoAdmin',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.onSurface),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text('Settings',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.02)),
                const SizedBox(height: 4),
                Text('Manage your administrator profile and platform configuration.',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13, color: AppColors.onSurfaceVariant)),
                const SizedBox(height: 24),

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
                                border: Border.all(color: AppColors.primary, width: 2.5),
                              ),
                              child: CircleAvatar(
                                radius: 38,
                                backgroundColor: AppColors.primaryContainer,
                                backgroundImage: user?.avatarUrl != null
                                    ? NetworkImage(user!.avatarUrl!)
                                    : null,
                                child: user?.avatarUrl == null
                                    ? Text(
                                        user?.displayName.isNotEmpty == true
                                            ? user!.displayName[0].toUpperCase()
                                            : 'A',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 28,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.primary),
                                      )
                                    : null,
                              ),
                            ),
                            Positioned(
                              bottom: 0,
                              right: 0,
                              child: Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: AppColors.primaryBright,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 2),
                                ),
                                child: const Icon(Icons.camera_alt, color: Colors.white, size: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(user?.displayName ?? 'Admin User',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                      Text(
                        isSuperAdmin ? 'Super Administrator' : 'Senior Curriculum Director',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 13, color: AppColors.onSurfaceMuted),
                      ),
                      const SizedBox(height: 20),
                      _FormField(label: 'FULL NAME', value: user?.displayName ?? ''),
                      const SizedBox(height: 12),
                      _FormField(label: 'EMAIL ADDRESS', value: user?.email ?? ''),
                      const SizedBox(height: 12),
                      _DropdownField(label: 'TIMEZONE', value: 'GMT -05:00 (EST)'),
                      const SizedBox(height: 12),
                      _DropdownField(label: 'LANGUAGE', value: 'English (US)'),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: () {},
                          child: Text('SAVE CHANGES',
                              style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.w700, letterSpacing: 0.05)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

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
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.notifications_outlined,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text('Notifications',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                const SizedBox(height: 16),

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
                              color: AppColors.primaryContainer,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.shield_outlined,
                                color: AppColors.primary, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Text('Security & Access',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 16, fontWeight: FontWeight.w700)),
                        ],
                      ),
                      const SizedBox(height: 16),
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
                      Text('ACTIVE SESSIONS',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.08,
                              color: AppColors.onSurfaceMuted)),
                      const SizedBox(height: 10),
                      _SessionRow(
                        device: 'MacBook Pro - San Francisco, USA',
                        subtitle: 'Current Session',
                        isCurrent: true,
                      ),
                      const SizedBox(height: 8),
                      _SessionRow(
                        device: 'iPhone 15 - San Francisco, USA',
                        subtitle: 'Active 2 hours ago',
                        isCurrent: false,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Switch to User Zone — only visible for whitelisted accounts
                if (auth.hasUserZoneAccess) ...[
                  _UserZoneSwitchCard(user: user),
                  const SizedBox(height: 16),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
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
        Text(widget.label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
                color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 4),
        TextField(
          controller: _ctrl,
          style: GoogleFonts.spaceGrotesk(fontSize: 14),
          decoration: const InputDecoration(isDense: true),
        ),
      ],
    );
  }
}

class _DropdownField extends StatelessWidget {
  final String label;
  final String value;
  const _DropdownField({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.08,
                color: AppColors.onSurfaceMuted)),
        const SizedBox(height: 4),
        DropdownButtonFormField<String>(
          value: value,
          items: [DropdownMenuItem(value: value, child: Text(value))],
          onChanged: (_) {},
          style: GoogleFonts.spaceGrotesk(fontSize: 14, color: AppColors.onSurface),
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
              Text(title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(subtitle,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _SecurityRow extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;

  const _SecurityRow({required this.label, required this.subtitle, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: AppColors.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(subtitle,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: AppColors.onSurfaceMuted),
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
          color: AppColors.onSurfaceVariant,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(device,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(subtitle,
                  style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        if (!isCurrent)
          GestureDetector(
            onTap: () {},
            child: Text('LOG OUT',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.error)),
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
            colors: [Color(0xFF0A192F), Color(0xFF213145)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.swap_horiz_rounded,
                  color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Switch to User Zone',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                  const SizedBox(height: 2),
                  Text('Open LexiLingo as a learner',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 11, color: Colors.white54)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryBright,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text('SWITCH',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      letterSpacing: 0.06)),
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
    final initials = displayName.isNotEmpty ? displayName[0].toUpperCase() : 'A';

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          const SizedBox(height: 12),
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.surfaceContainerHigh,
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
                colors: [Color(0xFF0A192F), Color(0xFF152840)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 28,
                      backgroundColor: AppColors.primaryContainer,
                      child: Text(initials,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary)),
                    ),
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBright,
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFF0A192F), width: 2),
                        ),
                        child: const Icon(Icons.school_outlined,
                            color: Colors.white, size: 10),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(displayName,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      Text(email,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11, color: Colors.white54),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: AppColors.primaryBright,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isSuperAdmin ? 'SUPER ADMIN' : 'ADMIN',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                              letterSpacing: 0.06),
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
                Text('Your dual account',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700,
                        color: AppColors.onSurface)),
                const SizedBox(height: 8),
                Text(
                  'Your admin account is linked to a LexiLingo learner profile with the same email. '
                  'Open the LexiLingo app on your device to continue as a learner — '
                  'you\'ll be logged in automatically if you use the same email.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, color: AppColors.onSurfaceVariant, height: 1.5),
                ),
                const SizedBox(height: 20),
                // Step cards
                _StepRow(
                  step: '1',
                  text: 'Open the LexiLingo app on your device',
                ),
                const SizedBox(height: 10),
                _StepRow(
                  step: '2',
                  text: 'Sign in with $email',
                ),
                const SizedBox(height: 10),
                _StepRow(
                  step: '3',
                  text: 'Your learner progress and data will be ready',
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
          // Buttons
          Padding(
            padding: EdgeInsets.fromLTRB(
                20, 0, 20, MediaQuery.of(context).padding.bottom + 20),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text('Open LexiLingo App',
                        style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700, fontSize: 14)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryBright,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('Dismiss',
                      style: GoogleFonts.spaceGrotesk(
                          color: AppColors.onSurfaceMuted,
                          fontWeight: FontWeight.w600)),
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
            color: AppColors.primaryContainer,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(step,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(text,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, color: AppColors.onSurface)),
        ),
      ],
    );
  }
}
