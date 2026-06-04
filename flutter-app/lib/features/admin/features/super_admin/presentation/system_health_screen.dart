import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../auth/presentation/auth_provider.dart';

class SystemHealthScreen extends StatefulWidget {
  const SystemHealthScreen({super.key});

  @override
  State<SystemHealthScreen> createState() => _SystemHealthScreenState();
}

class _SystemHealthScreenState extends State<SystemHealthScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  Timer? _refreshTimer;

  final List<Map<String, dynamic>> _logs = [
    {'time': '14:02:11', 'level': 'INFO', 'msg': 'Connection established to cluster-node-04'},
    {'time': '14:02:12', 'level': 'SUCCESS', 'msg': 'Health check passed for API Gateway v2.4'},
    {'time': '14:02:15', 'level': 'DEBUG', 'msg': 'Latency spike detected in US-East-1 (342ms)'},
    {'time': '14:02:18', 'level': 'WARN', 'msg': 'Memory threshold reached on shard-alpha (85%)'},
    {'time': '14:02:22', 'level': 'INFO', 'msg': 'Scaling group initialized: spawning node...'},
    {'time': '14:02:30', 'level': 'INFO', 'msg': 'System access → tail -f /var/log/syslog'},
  ];

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
    try {
      // monitoring/system returns raw JSON — no ApiResponse wrapper
      final resp = await ApiClient.instance.get('/admin/monitoring/system');
      if (mounted) setState(() { _data = resp; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isSuperAdmin = context.watch<AuthProvider>().isSuperAdmin;
    if (!isSuperAdmin) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
            onPressed: () => context.pop(),
          ),
          title: Text('System Core Health',
              style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.errorContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.lock_outlined,
                      color: AppColors.error, size: 36),
                ),
                const SizedBox(height: 20),
                Text('Access Restricted',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 20, fontWeight: FontWeight.w700,
                        color: AppColors.onSurface)),
                const SizedBox(height: 8),
                Text('System monitoring is only accessible to Super Administrators.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 13, color: AppColors.onSurfaceMuted)),
              ],
            ),
          ),
        ),
      );
    }
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
            icon: const Icon(Icons.refresh, color: AppColors.primary),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Real-time infrastructure monitoring and terminal access.',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 13, color: AppColors.onSurfaceVariant)),
                  const SizedBox(height: 16),
                  // Health metrics
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
                        value: _data != null
                            ? '${(_data!['cpu_percent'] as num?)?.toStringAsFixed(1) ?? '--'}%'
                            : '--',
                        icon: Icons.memory_outlined,
                        healthy: ((_data?['cpu_percent'] as num?) ?? 0) < 80,
                      ),
                      _HealthStat(
                        label: 'MEM USAGE',
                        value: _data != null
                            ? '${(_data!['memory'] as Map?)?['percent']?.toStringAsFixed(0) ?? '--'}%'
                            : '--',
                        icon: Icons.storage_outlined,
                        healthy: ((_data?['memory'] as Map?)?['percent'] as num? ?? 0) < 85,
                      ),
                      _HealthStat(
                        label: 'DISK USED',
                        value: _data != null
                            ? '${(_data!['disk'] as Map?)?['percent']?.toStringAsFixed(0) ?? '--'}%'
                            : '--',
                        icon: Icons.speed_outlined,
                        healthy: ((_data?['disk'] as Map?)?['percent'] as num? ?? 0) < 80,
                      ),
                      _HealthStat(
                        label: 'LOAD AVG',
                        value: _data != null
                            ? '${(_data!['load_avg'] as Map?)?['1m']?.toStringAsFixed(2) ?? '--'}'
                            : '--',
                        icon: Icons.hub_outlined,
                        healthy: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Live Terminal Log
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF0D1117),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.terminal, color: Colors.white60, size: 18),
                            const SizedBox(width: 8),
                            Text('Live Terminal Log',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                            const Spacer(),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.amber,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Container(
                              width: 10,
                              height: 10,
                              decoration: const BoxDecoration(
                                color: Colors.green,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ..._logs.map((log) => _TerminalLine(log: log)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Traffic Distribution
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('Traffic Distribution',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const Icon(Icons.public, color: AppColors.primary, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _TrafficBar(region: 'NORTH AMERICA', pct: 0.45),
                        const SizedBox(height: 8),
                        _TrafficBar(region: 'EUROPE', pct: 0.30),
                        const SizedBox(height: 8),
                        _TrafficBar(region: 'ASIA PACIFIC', pct: 0.25),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // System Status Gauges
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('System Status Gauges',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 16),
                        Center(
                          child: Column(
                            children: [
                              Text('98.2',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 48,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.primary,
                                      letterSpacing: -0.03)),
                              Text('UPTIME %',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.08,
                                      color: AppColors.onSurfaceMuted)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceAround,
                          children: [
                            _GaugeSmall(label: 'HTTP ERRORS', value: '0.02%', danger: false),
                            _GaugeSmall(label: 'DB CONNECTIONS', value: '1,422', danger: false),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Security Threats
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Security Threats',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _ThreatRow(
                          icon: Icons.block_outlined,
                          title: 'SQL Injection Attempt',
                          detail: 'IP: 192.168.1.42 • 4m ago',
                          status: 'BLOCKED',
                          statusColor: AppColors.error,
                        ),
                        const Divider(height: 16),
                        _ThreatRow(
                          icon: Icons.warning_outlined,
                          title: 'Failed Login Spree',
                          detail: 'User ID: #8821 • 12m ago',
                          status: 'THROTTLED',
                          statusColor: AppColors.warning,
                        ),
                        const Divider(height: 16),
                        _ThreatRow(
                          icon: Icons.admin_panel_settings_outlined,
                          title: 'New Admin Session',
                          detail: 'ID: SuperAdmin_09 • 45m ago',
                          status: 'LOGGED',
                          statusColor: AppColors.success,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _HealthStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool healthy;

  const _HealthStat({
    required this.label,
    required this.value,
    required this.icon,
    required this.healthy,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 15),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 20, fontWeight: FontWeight.w700,
                  color: AppColors.onSurface, letterSpacing: -0.02)),
        ],
      ),
    );
  }
}

class _TerminalLine extends StatelessWidget {
  final Map<String, dynamic> log;
  const _TerminalLine({required this.log});

  Color get _levelColor {
    switch (log['level']) {
      case 'SUCCESS': return Colors.greenAccent;
      case 'WARN': return Colors.amber;
      case 'DEBUG': return Colors.cyanAccent;
      case 'ERROR': return Colors.redAccent;
      default: return Colors.white54;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: RichText(
        text: TextSpan(
          style: GoogleFonts.sourceCodePro(fontSize: 11),
          children: [
            TextSpan(text: '[${log['time']}] ', style: const TextStyle(color: Colors.white38)),
            TextSpan(
                text: '${log['level']}: ',
                style: TextStyle(color: _levelColor, fontWeight: FontWeight.bold)),
            TextSpan(text: log['msg'], style: const TextStyle(color: Colors.white70)),
          ],
        ),
      ),
    );
  }
}

class _TrafficBar extends StatelessWidget {
  final String region;
  final double pct;
  const _TrafficBar({required this.region, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(region,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
            Text('${(pct * 100).toInt()}%',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: pct,
            backgroundColor: AppColors.surfaceContainerHigh,
            valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            minHeight: 6,
          ),
        ),
      ],
    );
  }
}

class _GaugeSmall extends StatelessWidget {
  final String label;
  final String value;
  final bool danger;
  const _GaugeSmall({required this.label, required this.value, required this.danger});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: danger ? AppColors.error : AppColors.onSurface,
                letterSpacing: -0.02)),
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 9, fontWeight: FontWeight.w700,
                letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
      ],
    );
  }
}

class _ThreatRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final String status;
  final Color statusColor;

  const _ThreatRow({
    required this.icon,
    required this.title,
    required this.detail,
    required this.status,
    required this.statusColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: statusColor),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
              Text(detail,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11, color: AppColors.onSurfaceMuted)),
            ],
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: statusColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(status,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700, color: statusColor)),
        ),
      ],
    );
  }
}
