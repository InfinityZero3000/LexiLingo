import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../core/constants/app_colors.dart';

/// KPI card with an animated count-up on first paint.
/// The count animates from 0 to [value] over [duration] using [curve].
class KpiCountCard extends StatefulWidget {
  final String label;
  final double value;
  final String suffix;
  final IconData icon;
  final String? change;
  final bool changePositive;
  final Color? iconColor;
  final Color? iconBg;
  final Duration duration;
  final Curve curve;
  final VoidCallback? onTap;

  const KpiCountCard({
    super.key,
    required this.label,
    required this.value,
    this.suffix = '',
    required this.icon,
    this.change,
    this.changePositive = true,
    this.iconColor,
    this.iconBg,
    this.duration = const Duration(milliseconds: 1200),
    this.curve = Curves.easeOutCubic,
    this.onTap,
  });

  @override
  State<KpiCountCard> createState() => _KpiCountCardState();
}

class _KpiCountCardState extends State<KpiCountCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: widget.duration);
    _anim = CurvedAnimation(parent: _ctrl, curve: widget.curve);
    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _format(double v) {
    if (v >= 1000000) return '${(v / 1000000).toStringAsFixed(1)}M';
    if (v >= 1000) return '${(v / 1000).toStringAsFixed(1)}K';
    if (v == v.truncateToDouble()) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = widget.iconColor ?? AppColors.primary;
    final iconBg = widget.iconBg ?? AppColors.primaryContainer;

    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: iconBg,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.icon, color: iconColor, size: 16),
                ),
                const Spacer(),
                if (widget.change != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: widget.changePositive
                          ? AppColors.successContainer
                          : AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      widget.change!,
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: widget.changePositive
                            ? AppColors.success
                            : AppColors.error,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.label.toUpperCase(),
              style: GoogleFonts.spaceGrotesk(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.06,
                color: AppColors.onSurfaceMuted,
              ),
            ),
            const SizedBox(height: 3),
            AnimatedBuilder(
              animation: _anim,
              builder: (_, __) {
                final current = widget.value * _anim.value;
                return Text(
                  _format(current) + widget.suffix,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.02,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
