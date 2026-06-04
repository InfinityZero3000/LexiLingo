import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      // analytics returns raw JSON — no ApiResponse wrapper
      final resp = await ApiClient.instance.get('/admin/analytics/dashboard/kpis');
      if (mounted) setState(() { _data = resp['kpis'] as Map<String, dynamic>?; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _formatNum(dynamic n) {
    final num v = n is num ? n : (double.tryParse(n.toString()) ?? 0);
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    return v.toStringAsFixed(v == v.truncate() ? 0 : 1);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('Content Analytics',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.calendar_today_outlined, size: 14),
            label: Text('Last 30 Days',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.download_outlined, size: 14),
            label: Text('Export',
                style: GoogleFonts.spaceGrotesk(fontSize: 11, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Text(
                    'Real-time performance tracking for global linguistic assets.',
                    style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  _AnalyticStat(
                    label: 'TOTAL USERS',
                    value: _formatNum(_data?['total_users'] ?? 0),
                    change: 'All time',
                    icon: Icons.group_outlined,
                  ),
                  const SizedBox(height: 12),
                  _AnalyticStat(
                    label: 'ACTIVE 7D',
                    value: _formatNum(_data?['active_users_7d'] ?? 0),
                    change: 'Last 7 days',
                    icon: Icons.timer_outlined,
                  ),
                  const SizedBox(height: 12),
                  _AnalyticStat(
                    label: 'PUBLISHED COURSES',
                    value: _formatNum(_data?['total_courses'] ?? 0),
                    changePositive: true,
                    change: 'Live',
                    icon: Icons.check_circle_outline,
                  ),
                  const SizedBox(height: 12),
                  _AnalyticStat(
                    label: 'AVG DAU (30D)',
                    value: _formatNum(_data?['avg_dau_30d'] ?? 0),
                    change: '30-day avg',
                    icon: Icons.bar_chart_outlined,
                  ),
                  const SizedBox(height: 20),
                  // Chart
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
                        Text('Daily Active Users',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('User engagement over the last 14 days',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                        const SizedBox(height: 16),
                        SizedBox(
                          height: 100,
                          child: _LineChart(),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: ['01 May', '07 May', '14 May']
                              .map((l) => Text(l,
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 10, color: AppColors.onSurfaceMuted)))
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Popular Languages
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
                        Text('Popular Languages',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 16, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text('Course enrollment by volume',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                        const SizedBox(height: 16),
                        _LangProgress(lang: 'Spanish (ES)', pct: 0.42),
                        const SizedBox(height: 10),
                        _LangProgress(lang: 'French (FR)', pct: 0.28),
                        const SizedBox(height: 10),
                        _LangProgress(lang: 'Japanese (JA)', pct: 0.18),
                        const SizedBox(height: 10),
                        _LangProgress(lang: 'German (DE)', pct: 0.12),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () {},
                            child: Text('View All Regions',
                                style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // AI Insight card (dark)
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: AppColors.navy,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: AppColors.primaryBright,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.psychology_outlined,
                                  color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 10),
                            Text('AI Content Insight',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white)),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text('Machine learning recommendations',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 11, color: Colors.white38)),
                        const SizedBox(height: 12),
                        Text(
                          '"Increasing gamified quiz density in Level 2 French could boost retention by an estimated 14% based on current user flow drop-offs."',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13, color: Colors.white70, fontStyle: FontStyle.italic),
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () {},
                          style: ElevatedButton.styleFrom(backgroundColor: AppColors.primaryBright),
                          child: Text('Apply Suggested Optimizations',
                              style: GoogleFonts.spaceGrotesk(
                                  fontWeight: FontWeight.w700, fontSize: 12)),
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

class _AnalyticStat extends StatelessWidget {
  final String label;
  final String value;
  final String change;
  final bool changePositive;
  final IconData icon;

  const _AnalyticStat({
    required this.label,
    required this.value,
    required this.change,
    this.changePositive = true,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: AppColors.primary, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.08,
                        color: AppColors.onSurfaceMuted)),
                Text(value,
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.onSurface,
                        letterSpacing: -0.03)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: changePositive ? AppColors.successContainer : AppColors.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(change,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: changePositive ? AppColors.success : AppColors.error)),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final points = [0.3, 0.5, 0.4, 0.7, 0.6, 0.8, 0.75, 0.65, 0.7, 0.9, 0.85, 0.8, 0.75, 0.9];
    return CustomPaint(painter: _LineChartPainter(points: points));
  }
}

class _LineChartPainter extends CustomPainter {
  final List<double> points;
  const _LineChartPainter({required this.points});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    final paint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final fillPaint = Paint()
      ..color = AppColors.primaryContainer.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    final w = size.width / (points.length - 1);
    final path = Path();
    final fillPath = Path();

    for (var i = 0; i < points.length; i++) {
      final x = i * w;
      final y = size.height * (1 - points[i]);
      if (i == 0) {
        path.moveTo(x, y);
        fillPath.moveTo(x, size.height);
        fillPath.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fillPath.lineTo(x, y);
      }
    }
    fillPath.lineTo(size.width, size.height);
    fillPath.close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_) => false;
}

class _LangProgress extends StatelessWidget {
  final String lang;
  final double pct;
  const _LangProgress({required this.lang, required this.pct});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(lang,
                style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurface)),
            Text('${(pct * 100).toInt()}%',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.onSurface)),
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
