import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';

class SuperDashboardScreen extends StatefulWidget {
  const SuperDashboardScreen({super.key});

  @override
  State<SuperDashboardScreen> createState() => _SuperDashboardScreenState();
}

class _SuperDashboardScreenState extends State<SuperDashboardScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // monitoring returns raw JSON — no ApiResponse wrapper
      final resp = await ApiClient.instance.get('/admin/monitoring/system');
      if (mounted) setState(() { _data = resp; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.onSurface),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            Text('Super Admin Dashboard',
                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16)),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text('SUPER ADMIN MODE',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 8, fontWeight: FontWeight.w700, color: Colors.white)),
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
                  Text('SYSTEM OVERSIGHT',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.08,
                          color: AppColors.primary)),
                  const SizedBox(height: 4),
                  Text('Super Admin Dashboard',
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 26,
                          fontWeight: FontWeight.w700,
                          color: AppColors.onSurface,
                          letterSpacing: -0.02)),
                  const SizedBox(height: 16),
                  // System Reboot button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.bolt, size: 16),
                      label: Text('SYSTEM REBOOT',
                          style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700, letterSpacing: 0.05)),
                      style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBright),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Global System Health
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
                            Text('Global System Health',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.successContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      color: AppColors.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text('OPTIMAL',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 9,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.success)),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text('Live performance across all regional clusters',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                        const SizedBox(height: 16),
                        _MetricRow(label: 'UPTIME', value: _data?['uptime'] ?? '99.98%'),
                        const SizedBox(height: 8),
                        _MetricRow(label: 'LATENCY', value: _data?['latency'] ?? '42ms'),
                        const SizedBox(height: 8),
                        _MetricRow(label: 'THROUGHPUT', value: _data?['throughput'] ?? '1.2GB/s'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Live Concurrent Users
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.primaryBright,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.people_outline,
                                  color: Colors.white60, size: 24),
                              const SizedBox(height: 8),
                              Text(_data?['concurrent_users'] ?? '242.8k',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      letterSpacing: -0.03)),
                              Text('LIVE CONCURRENT USERS',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.05,
                                      color: Colors.white60)),
                            ],
                          ),
                        ),
                        const Icon(Icons.trending_up, color: Colors.white60, size: 32),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Audit Trail
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
                            Text('Audit Trail',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 16, fontWeight: FontWeight.w700)),
                            const Icon(Icons.history, color: AppColors.onSurfaceMuted, size: 20),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AuditRow(
                          icon: Icons.security_outlined,
                          title: 'Security Protocol Updated',
                          detail: 'Region: North America • 2m ago',
                          color: AppColors.primary,
                        ),
                        const Divider(height: 16),
                        _AuditRow(
                          icon: Icons.person_add_outlined,
                          title: 'New Super Admin: Elena R.',
                          detail: 'Permission: Global Access • 15m ago',
                          color: AppColors.primary,
                        ),
                        const Divider(height: 16),
                        _AuditRow(
                          icon: Icons.storage_outlined,
                          title: 'DB Migration Complete',
                          detail: 'Zone: EU-West-1 • 1h ago',
                          color: AppColors.success,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Performance Matrix
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
                        Text('Performance Matrix',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        _MatrixHeader(),
                        const Divider(height: 12),
                        _MatrixRow(region: 'North America East', load: '66%', errors: '0.01%', status: 'STABLE', statusOk: true),
                        _MatrixRow(region: 'Europe Central', load: '92%', errors: '0.05%', status: 'HIGH LOAD', statusOk: false),
                        _MatrixRow(region: 'Asia Pacific South', load: '34%', errors: '0.00%', status: 'STABLE', statusOk: true),
                        _MatrixRow(region: 'South America East', load: '12%', errors: '0.02%', status: 'STABLE', statusOk: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Navigate to full health screen
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push('/settings/system-health'),
                      icon: const Icon(Icons.monitor_heart_outlined, size: 16),
                      label: Text('View System Core Health',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _MetricRow extends StatelessWidget {
  final String label;
  final String value;
  const _MetricRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 11, fontWeight: FontWeight.w700,
                letterSpacing: 0.05, color: AppColors.onSurfaceMuted)),
        Text(value,
            style: GoogleFonts.spaceGrotesk(
                fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
      ],
    );
  }
}

class _AuditRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  final Color color;
  const _AuditRow({required this.icon, required this.title, required this.detail, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 16),
        ),
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
      ],
    );
  }
}

class _MatrixHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(flex: 2, child: Text('REGION', style: _headerStyle)),
        Expanded(child: Text('LOAD', style: _headerStyle)),
        Expanded(child: Text('ERRORS', style: _headerStyle)),
        Expanded(child: Text('STATUS', style: _headerStyle)),
      ],
    );
  }

  TextStyle get _headerStyle => GoogleFonts.spaceGrotesk(
      fontSize: 9, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted);
}

class _MatrixRow extends StatelessWidget {
  final String region;
  final String load;
  final String errors;
  final String status;
  final bool statusOk;

  const _MatrixRow({
    required this.region,
    required this.load,
    required this.errors,
    required this.status,
    required this.statusOk,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
              flex: 2,
              child: Text(region,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 12, color: AppColors.onSurface))),
          Expanded(
              child: Text(load,
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurface))),
          Expanded(
              child: Text(errors,
                  style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurface))),
          Expanded(
              child: Text(status,
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: statusOk ? AppColors.success : AppColors.error))),
        ],
      ),
    );
  }
}
