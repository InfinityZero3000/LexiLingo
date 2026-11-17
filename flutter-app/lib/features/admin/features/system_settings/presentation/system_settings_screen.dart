import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class SystemSettingsScreen extends StatefulWidget {
  const SystemSettingsScreen({super.key});

  @override
  State<SystemSettingsScreen> createState() => _SystemSettingsScreenState();
}

class _SystemSettingsScreenState extends State<SystemSettingsScreen> {
  Map<String, dynamic>? _config;
  bool _loading = true;
  bool _saving = false;

  late TextEditingController _appNameCtrl;
  late TextEditingController _tokenExpiryCtrl;
  late TextEditingController _refreshDaysCtrl;
  late TextEditingController _aiUrlCtrl;
  late TextEditingController _corsCtrl;
  String? _error;
  String _logLevel = 'INFO';
  bool _debugMode = false;
  int _tokenExpiry = 30;
  int _refreshDays = 7;

  static const _logLevels = ['DEBUG', 'INFO', 'WARNING', 'ERROR'];

  @override
  void initState() {
    super.initState();
    _appNameCtrl = TextEditingController();
    _tokenExpiryCtrl = TextEditingController();
    _refreshDaysCtrl = TextEditingController();
    _aiUrlCtrl = TextEditingController();
    _corsCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _appNameCtrl.dispose();
    _tokenExpiryCtrl.dispose();
    _refreshDaysCtrl.dispose();
    _aiUrlCtrl.dispose();
    _corsCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.instance.get(ApiEndpoints.systemInfo);
      final data = resp['data'] ?? resp;
      if (mounted) {
        setState(() {
          _config = data as Map<String, dynamic>?;
          _appNameCtrl.text = (_config?['app_name'] ?? 'LexiLingo').toString();
          _logLevel = (_config?['log_level'] ?? 'INFO').toString();
          _debugMode = (_config?['debug'] as bool?) ?? false;
          _tokenExpiry =
              (_config?['token_expire_minutes'] as num?)?.toInt() ?? 30;
          _refreshDays = (_config?['refresh_token_days'] as num?)?.toInt() ?? 7;
          _tokenExpiryCtrl.text = _tokenExpiry.toString();
          _refreshDaysCtrl.text = _refreshDays.toString();
          _aiUrlCtrl.text = (_config?['ai_service_url'] ?? '').toString();
          final origins = _config?['cors_origins'];
          _corsCtrl.text = origins is List
              ? origins.join(', ')
              : (origins ?? '').toString();
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not load settings.';
          _loading = false;
        });
      }
    }
  }

  Future<void> _save() async {
    final tokenExpiry = int.tryParse(_tokenExpiryCtrl.text.trim());
    final refreshDays = int.tryParse(_refreshDaysCtrl.text.trim());
    if (_appNameCtrl.text.trim().isEmpty ||
        tokenExpiry == null ||
        tokenExpiry <= 0 ||
        refreshDays == null ||
        refreshDays <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'App name is required and expiry values must be positive.',
            style: GoogleFonts.spaceGrotesk(),
          ),
          backgroundColor: AdminColors.error,
        ),
      );
      return;
    }
    _tokenExpiry = tokenExpiry;
    _refreshDays = refreshDays;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put(
        ApiEndpoints.systemInfo,
        data: {
          'app_name': _appNameCtrl.text.trim(),
          'log_level': _logLevel,
          'debug': _debugMode,
          'token_expire_minutes': _tokenExpiry,
          'refresh_token_days': _refreshDays,
          'ai_service_url': _aiUrlCtrl.text.trim(),
          'cors_origins': _corsCtrl.text.trim(),
        },
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settings saved', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AdminColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed.', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AdminColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      appBar: AppBar(
        backgroundColor: AdminColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AdminColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text(
          'System Config',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.refresh_outlined,
              color: AdminColors.onSurface,
            ),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: SkeletonBox(height: 320, borderRadius: 16),
            )
          : _error != null && _config == null
          ? _SettingsError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'System Configuration',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AdminColors.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Global app settings — changes apply immediately.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AdminColors.onSurfaceMuted,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xl),

                    // App info card
                    _card(
                      label: 'APP INFO',
                      child: Column(
                        children: [
                          _fieldLabel('App Name'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _appNameCtrl,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: const InputDecoration(isDense: true),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _infoRow(
                            'API prefix',
                            (_config?['api_prefix'] ?? '—').toString(),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          _infoRow(
                            'Environment',
                            (_config?['app_env'] ?? '—').toString(),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Logging card
                    _card(
                      label: 'LOGGING',
                      child: Column(
                        children: [
                          _fieldLabel('Log Level'),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: _logLevel,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: AdminColors.onSurface),
                            decoration: const InputDecoration(isDense: true),
                            items: _logLevels
                                .map(
                                  (l) => DropdownMenuItem(
                                    value: l,
                                    child: Text(l),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _logLevel = v ?? _logLevel),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _toggleRow(
                            title: 'Debug Mode',
                            subtitle:
                                'Enables verbose logging and debug endpoints',
                            value: _debugMode,
                            onChanged: (v) => setState(() => _debugMode = v),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),

                    // Auth card
                    _card(
                      label: 'AUTHENTICATION',
                      child: Column(
                        children: [
                          _fieldLabel('Access Token Expiry (minutes)'),
                          const SizedBox(height: 6),
                          TextField(
                            keyboardType: TextInputType.number,
                            controller: _tokenExpiryCtrl,
                            onChanged: (v) =>
                                _tokenExpiry = int.tryParse(v) ?? _tokenExpiry,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: const InputDecoration(isDense: true),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Text(
                            'Current: $_tokenExpiry minutes',
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: AdminColors.onSurfaceMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _card(
                      label: 'SERVICES & SECURITY',
                      child: Column(
                        children: [
                          _fieldLabel('Refresh Token Expiry (days)'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _refreshDaysCtrl,
                            keyboardType: TextInputType.number,
                            onChanged: (v) =>
                                _refreshDays = int.tryParse(v) ?? _refreshDays,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: const InputDecoration(isDense: true),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _fieldLabel('AI Service URL'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _aiUrlCtrl,
                            keyboardType: TextInputType.url,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: const InputDecoration(isDense: true),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          _fieldLabel('Allowed CORS Origins'),
                          const SizedBox(height: 6),
                          TextField(
                            controller: _corsCtrl,
                            maxLines: 2,
                            style: Theme.of(context).textTheme.bodyMedium,
                            decoration: const InputDecoration(isDense: true),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),

                    // Save button
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        style: FilledButton.styleFrom(
                          backgroundColor: AdminColors.primaryBright,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.md),
                          ),
                        ),
                        icon: _saving
                            ? SizedBox(
                                width: AppSpacing.lg,
                                height: 16,
                                child: CircularProgressIndicator(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimary,
                                  strokeWidth: 2,
                                ),
                              )
                            : Icon(
                                Icons.save_outlined,
                                color: Theme.of(context).colorScheme.onPrimary,
                                size: 18,
                              ),
                        label: Text(
                          'Save Changes',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: Theme.of(context).colorScheme.onPrimary,
                              ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _card({required String label, required Widget child}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AdminColors.onSurfaceMuted,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AdminColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: AdminColors.outline, width: 0.5),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) => Text(
    label,
    style: Theme.of(context).textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: AdminColors.onSurfaceMuted,
      letterSpacing: 0.5,
    ),
  );

  Widget _infoRow(String key, String value) => Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        key,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
      ),
      Text(
        value,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: AdminColors.onSurface,
        ),
      ),
    ],
  );

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) => Row(
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

class _SettingsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SettingsError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: AdminColors.error, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Could not load settings',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ),
        ],
      ),
    ),
  );
}
