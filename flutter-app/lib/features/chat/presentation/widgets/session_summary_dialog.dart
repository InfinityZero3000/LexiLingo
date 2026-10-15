import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// End-of-session summary shown after the learner ends a topic chat —
/// mirrors a Duolingo-style lesson-complete card. Every number shown here
/// is real (session-local counters + the learner's actual streak/XP), never
/// a fabricated per-session reward.
class SessionSummaryDialog extends StatelessWidget {
  final int mistakesSaved;
  final int wordsSaved;
  final int currentStreak;
  final int? totalXp;

  const SessionSummaryDialog({
    super.key,
    required this.mistakesSaved,
    required this.wordsSaved,
    required this.currentStreak,
    this.totalXp,
  });

  static Future<void> show(
    BuildContext context, {
    required int mistakesSaved,
    required int wordsSaved,
    required int currentStreak,
    int? totalXp,
  }) {
    return showDialog(
      context: context,
      builder: (_) => SessionSummaryDialog(
        mistakesSaved: mistakesSaved,
        wordsSaved: wordsSaved,
        currentStreak: currentStreak,
        totalXp: totalXp,
      ),
    );
  }

  bool get _hasActivity => mistakesSaved > 0 || wordsSaved > 0;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _hasActivity
                  ? Icons.celebration_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 48,
              color: accent,
            ),
            const SizedBox(height: 12),
            Text(
              'topicChat.sessionSummaryTitle'.tr(),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              _hasActivity
                  ? 'topicChat.sessionSummarySubtitle'.tr()
                  : 'topicChat.sessionSummaryEmptySubtitle'.tr(),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorRoles.textMuted(isDark),
              ),
              textAlign: TextAlign.center,
            ),
            if (_hasActivity) ...[
              const SizedBox(height: 20),
              SizedBox(
                height: 120,
                child: _SessionBarChart(
                  mistakesSaved: mistakesSaved,
                  wordsSaved: wordsSaved,
                  isDark: isDark,
                ),
              ),
            ],
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _StatChip(
                  icon: Icons.local_fire_department_rounded,
                  label: 'topicChat.streakStat'.tr(
                    namedArgs: {'count': '$currentStreak'},
                  ),
                  color: AppColors.orange,
                ),
                if (totalXp != null)
                  _StatChip(
                    icon: Icons.bolt_rounded,
                    label: 'topicChat.xpStat'.tr(
                      namedArgs: {'count': '$totalXp'},
                    ),
                    color: AppColors.accentYellow,
                  ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accent,
                  foregroundColor: Theme.of(context).colorScheme.surface,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text('topicChat.sessionSummaryDone'.tr()),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SessionBarChart extends StatelessWidget {
  final int mistakesSaved;
  final int wordsSaved;
  final bool isDark;

  const _SessionBarChart({
    required this.mistakesSaved,
    required this.wordsSaved,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final maxY = [mistakesSaved, wordsSaved]
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final labels = [
      'topicChat.mistakesCorrectedLabel'.tr(),
      'topicChat.newWordsLabel'.tr(),
    ];
    final values = [mistakesSaved.toDouble(), wordsSaved.toDouble()];
    final colors = [AppColors.orange, AppColorRoles.primary(isDark)];

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.3,
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: AppColorRoles.textMuted(isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < values.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: values[i],
                  width: 36,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(8),
                  ),
                  color: colors[i],
                ),
              ],
              showingTooltipIndicators: values[i] > 0 ? [0] : [],
            ),
        ],
        barTouchData: BarTouchData(
          enabled: false,
          touchTooltipData: BarTouchTooltipData(
            getTooltipColor: (_) => Colors.transparent,
            tooltipPadding: EdgeInsets.zero,
            tooltipMargin: 4,
            getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
              '${rod.toY.round()}',
              TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 13,
                color: colors[groupIndex],
              ),
            ),
          ),
        ),
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _StatChip({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
