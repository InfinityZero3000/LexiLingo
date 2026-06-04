import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

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
  String _logLevel = 'INFO';
  bool _debugMode = false;
  int _tokenExpiry = 3600;

  static const _logLevels = ['DEBUG', 'INFO', 'WARNING', 'ERROR'];

  @override
  void initState() {
    super.initState();
    _appNameCtrl = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _appNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.instance.get('/admin/system-info');
      final data = resp['data'] ?? resp;
      if (mounted) {
        setState(() {
          _config = data as Map<String, dynamic>?;
          _appNameCtrl.text = (_config?['app_name'] ?? 'LexiLingo').toString();
          _logLevel = (_config?['log_level'] ?? 'INFO').toString();
          _debugMode = (_config?['debug_mode'] as bool?) ?? false;
          _tokenExpiry = (_config?['token_expiration'] as num?)?.toInt() ?? 3600;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await ApiClient.instance.put('/admin/system-info', body: {
        'app_name': _appNameCtrl.text.trim(),
        'log_level': _logLevel,
        'debug_mode': _debugMode,
        'token_expiration': _tokenExpiry,
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Settings saved', style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e', style: GoogleFonts.spaceGrotesk()),
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
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
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
                        _infoRow('Version', (_config?['version'] ?? '—').toString()),
                        const SizedBox(height: 8),
                        _infoRow('Environment', (_config?['environment'] ?? 'production').toString()),
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
                          value: _logLevel,
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
                        _fieldLabel('Token Expiry (seconds)'),
                        const SizedBox(height: 6),
                        TextField(
                          keyboardType: TextInputType.number,
                          controller: TextEditingController(text: _tokenExpiry.toString()),
                          onChanged: (v) => _tokenExpiry = int.tryParse(v) ?? _tokenExpiry,
                          style: GoogleFonts.spaceGrotesk(fontSize: 14),
                          decoration: const InputDecoration(isDense: true),
                        ),
                        const SizedBox(height: 8),
                        Text('Current: ${(_tokenExpiry / 3600).toStringAsFixed(1)} hours',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                      ],
                    ),
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
          Switch(value: value, onChanged: onChanged, activeColor: AppColors.primary),
        ],
      );
}
