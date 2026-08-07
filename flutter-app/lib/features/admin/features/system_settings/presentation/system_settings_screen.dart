import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';

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
          _tokenExpiry = (_config?['token_expire_minutes'] as num?)?.toInt() ?? 30;
          _refreshDays = (_config?['refresh_token_days'] as num?)?.toInt() ?? 7;
          _tokenExpiryCtrl.text = _tokenExpiry.toString();
          _refreshDaysCtrl.text = _refreshDays.toString();
          _aiUrlCtrl.text = (_config?['ai_service_url'] ?? '').toString();
          final origins = _config?['cors_origins'];
          _corsCtrl.text = origins is List ? origins.join(', ') : (origins ?? '').toString();
          _error = null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() { _error = 'Could not load settings.'; _loading = false; });
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
          content: Text('App name is required and expiry values must be positive.',
              style: GoogleFonts.spaceGrotesk()),
          backgroundColor: AppColors.error,
        ),
      );
      return;
    }
    _tokenExpiry = tokenExpiry;
    _refreshDays = refreshDays;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put(ApiEndpoints.systemInfo, data: {
        'app_name': _appNameCtrl.text.trim(),
        'log_level': _logLevel,
        'debug': _debugMode,
        'token_expire_minutes': _tokenExpiry,
        'refresh_token_days': _refreshDays,
        'ai_service_url': _aiUrlCtrl.text.trim(),
        'cors_origins': _corsCtrl.text.trim(),
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settings saved', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed.', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.error,
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
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('System Config',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, color: AppColors.onSurface),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: AdminSkeleton(height: 320, borderRadius: 16),
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
                  Text('System Configuration',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                  const SizedBox(height: 4),
                  Text('Global app settings — changes apply immediately.',
                      style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
                  const SizedBox(height: 24),

                  // App info card
                  _card(
                    label: 'APP INFO',
                    child: Column(
                      children: [
                        _fieldLabel('App Name'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _appNameCtrl,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        const SizedBox(height: 16),
                        _infoRow('API prefix', (_config?['api_prefix'] ?? '—').toString()),
                        const SizedBox(height: 8),
                        _infoRow('Environment', (_config?['app_env'] ?? '—').toString()),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Logging card
                  _card(
                    label: 'LOGGING',
                    child: Column(
                      children: [
                        _fieldLabel('Log Level'),
                        const SizedBox(height: 6),
                        DropdownButtonFormField<String>(
                          initialValue: _logLevel,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14, color: AppColors.onSurface),
                          decoration: const InputDecoration(isDense: true),
                          items: _logLevels
                              .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                              .toList(),
                          onChanged: (v) => setState(() => _logLevel = v ?? _logLevel),
                        ),
                        const SizedBox(height: 16),
                        _toggleRow(
                          title: 'Debug Mode',
                          subtitle: 'Enables verbose logging and debug endpoints',
                          value: _debugMode,
                          onChanged: (v) => setState(() => _debugMode = v),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

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
                          onChanged: (v) => _tokenExpiry = int.tryParse(v) ?? _tokenExpiry,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        const SizedBox(height: 8),
                        Text('Current: $_tokenExpiry minutes',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  _card(
                    label: 'SERVICES & SECURITY',
                    child: Column(children: [
                      _fieldLabel('Refresh Token Expiry (days)'),
                      const SizedBox(height: 6),
                      TextField(controller: _refreshDaysCtrl, keyboardType: TextInputType.number,
                          onChanged: (v) => _refreshDays = int.tryParse(v) ?? _refreshDays,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true)),
                      const SizedBox(height: 16),
                      _fieldLabel('AI Service URL'),
                      const SizedBox(height: 6),
                      TextField(controller: _aiUrlCtrl, keyboardType: TextInputType.url,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true)),
                      const SizedBox(height: 16),
                      _fieldLabel('Allowed CORS Origins'),
                      const SizedBox(height: 6),
                      TextField(controller: _corsCtrl, maxLines: 2,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true)),
                    ]),
                  ),
                  const SizedBox(height: 32),

                  // Save button
                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBright,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      icon: _saving
                          ? const SizedBox(width: 16, height: 16,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.save_outlined, color: Colors.white, size: 18),
                      label: Text('Save Changes',
                          style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700, color: Colors.white, fontSize: 14)),
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
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 10, fontWeight: FontWeight.w700,
                color: AppColors.onSurfaceMuted, letterSpacing: 0.8)),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.outline, width: 0.5),
          ),
          child: child,
        ),
      ],
    );
  }

  Widget _fieldLabel(String label) => Text(label,
      style: GoogleFonts.spaceGrotesk(
          fontSize: 10, fontWeight: FontWeight.w700,
          color: AppColors.onSurfaceMuted, letterSpacing: 0.5));

  Widget _infoRow(String key, String value) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(key,
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceMuted)),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
        ],
      );

  Widget _toggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
                Text(subtitle,
                    style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
              ],
            ),
          ),
          Switch(value: value, onChanged: onChanged, activeThumbColor: AppColors.primary),
        ],
      );
}

class _SettingsError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _SettingsError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.error_outline, color: AppColors.error, size: 40),
      const SizedBox(height: 12),
      Text('Could not load settings', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text(message, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
      const SizedBox(height: 16),
      SizedBox(height: 44, child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
    ]),
  ));
}
