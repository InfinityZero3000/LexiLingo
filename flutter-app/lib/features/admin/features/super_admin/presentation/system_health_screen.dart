import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';

import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../auth/presentation/auth_provider.dart';

class SystemHealthScreen extends StatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
  Map<String, dynamic>? _system;
  Map<String, dynamic>? _services;
  Map<String, dynamic>? _dbStats;
  String? _error;
  bool _loading = true;
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) => _load());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final responses = await Future.wait([
      _getOrNull(ApiEndpoints.monitoringSystem),
      _getOrNull(ApiEndpoints.monitoringServices),
      _getOrNull(ApiEndpoints.monitoringDbStats),
    ]);
    if (!mounted) return;
    setState(() {
      _system = responses[0] ?? _system;
      _services = responses[1] ?? _services;
      _dbStats = responses[2] ?? _dbStats;
      _error = responses.any((response) => response == null)
          ? 'One or more monitoring services are unavailable.'
          : null;
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _getOrNull(String path) async {
    try {
      return await ApiClient.instance.get(path);
    } catch (_) {
      return null;
    }
  }

  String _percent(String section) {
    final value = (_system?[section] as Map?)?['percent'] as num?;
    return value == null ? '--' : '${value.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().isSuperAdmin) return _restricted(context);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('System Core Health',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Column(children: [
                AdminSkeleton(height: 180, borderRadius: 16),
                SizedBox(height: 12),
                AdminSkeleton(height: 180, borderRadius: 16),
              ]),
            )
          : _error != null && _system == null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      Text('Live infrastructure status • refreshes every 30 seconds',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13, color: AppColors.onSurfaceVariant)),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _InlineWarning(message: 'Some metrics could not be refreshed.'),
                      ],
                      const SizedBox(height: 16),
                      GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 1.4,
                        children: [
                          _HealthStat(
                            label: 'CPU LOAD',
                            value: _system?['cpu_percent'] is num
                                ? '${(_system!['cpu_percent'] as num).toStringAsFixed(1)}%'
                                : '--',
                            icon: Icons.memory_outlined,
                          ),
                          _HealthStat(label: 'MEMORY', value: _percent('memory'), icon: Icons.storage_outlined),
                          _HealthStat(label: 'DISK USED', value: _percent('disk'), icon: Icons.speed_outlined),
                          _HealthStat(
                            label: 'LOAD AVG',
                            value: ((_system?['load_avg'] as Map?)?['1m'] as num?)?.toStringAsFixed(2) ?? '--',
                            icon: Icons.hub_outlined,
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      _section(
                        'Service Status',
                        Icons.dns_outlined,
                        ['postgres', 'redis', 'ai_service'].map((key) {
                          final status = (_services?[key] ?? 'unknown').toString();
                          return _StatusRow(label: _serviceLabel(key), status: status);
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      _section(
                        'Database Overview',
                        Icons.storage_outlined,
                        ((_dbStats?['counts'] as Map?)?.entries ?? const <MapEntry<dynamic, dynamic>>[])
                            .map((entry) => _CountRow(
                                  label: entry.key.toString().replaceAll('_', ' '),
                                  value: entry.value?.toString() ?? '--',
                                ))
                            .toList(),
                        emptyText: 'Database statistics are unavailable.',
                      ),
                    ],
                  ),
                ),
    );
  }

  String _serviceLabel(String key) => switch (key) {
        'postgres' => 'PostgreSQL',
        'ai_service' => 'AI Service',
        _ => 'Redis',
      };

  Widget _section(String title, IconData icon, List<Widget> children, {String? emptyText}) => Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, color: AppColors.primary, size: 20),
            const SizedBox(width: 8),
            Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
          const SizedBox(height: 12),
          if (children.isEmpty)
            Text(emptyText ?? 'No data', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted))
          else
            ...children,
        ]),
      );

  Widget _restricted(BuildContext context) => Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: AppBackButton(icon: Icons.arrow_back, color: AppColors.onSurface, onPressed: () => context.pop()),
          title: Text('System Core Health', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        ),
        body: Center(child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.lock_outlined, color: AppColors.error, size: 48),
            const SizedBox(height: 16),
            Text('Access Restricted', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text('System monitoring is only accessible to Super Administrators.',
                textAlign: TextAlign.center,
                style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceMuted)),
          ]),
        )),
      );
}

class _HealthStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _HealthStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(icon, color: AppColors.primary, size: 22),
          const SizedBox(height: 6),
          Text(label, style: GoogleFonts.spaceGrotesk(fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted)),
          Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
        ]),
      );
}

class _StatusRow extends StatelessWidget {
  final String label;
  final String status;
  const _StatusRow({required this.label, required this.status});

  @override
  Widget build(BuildContext context) {
    final healthy = status == 'healthy';
    return SizedBox(
      height: 48,
      child: Row(children: [
        Expanded(child: Text(label, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))),
        Icon(healthy ? Icons.check_circle : Icons.warning_amber_rounded,
            color: healthy ? AppColors.success : AppColors.warning, size: 18),
        const SizedBox(width: 6),
        Text(status.replaceAll('_', ' ').toUpperCase(),
            style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700,
                color: healthy ? AppColors.success : AppColors.warning)),
      ]),
    );
  }
}

class _CountRow extends StatelessWidget {
  final String label;
  final String value;
  const _CountRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 44,
        child: Row(children: [
          Expanded(child: Text(label.toUpperCase(), style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted))),
          Text(value, style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700)),
        ]),
      );
}

class _InlineWarning extends StatelessWidget {
  final String message;
  const _InlineWarning({required this.message});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: AppColors.errorContainer, borderRadius: BorderRadius.circular(12)),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.error),
          const SizedBox(width: 8),
          Expanded(child: Text(message, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.error))),
        ]),
      );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 40),
          const SizedBox(height: 12),
          Text('Monitoring unavailable', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(message, textAlign: TextAlign.center, maxLines: 3, overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 16),
          SizedBox(height: 44, child: OutlinedButton(onPressed: onRetry, child: const Text('Retry'))),
        ]),
      ));
}
