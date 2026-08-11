import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/progress/domain/entities/weekly_progress_entity.dart';

/// 7-day XP trend line chart using fl_chart.
class XpLineChart extends StatelessWidget {
  final WeeklyProgressEntity weeklyProgress;

  const XpLineChart({super.key, required this.weeklyProgress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = weeklyProgress.weekProgress;

    if (days.isEmpty || weeklyProgress.totalXP == 0) {
      return _EmptyChart(isDark: isDark);
    }

    final primary = AppColorRoles.primary(isDark);
    final maxXP = weeklyProgress.maxDailyXP.toDouble();

    final spots = days.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.xpEarned.toDouble());
    }).toList();

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: (maxXP * 1.2).ceilToDouble(),
          clipData: const FlClipData.all(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (maxXP / 4).ceilToDouble().clamp(
              1,
              double.infinity,
            ),
            getDrawingHorizontalLine: (_) => FlLine(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
          ),
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
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      days[i].day,
                      style: TextStyle(
                        fontSize: 10,
                        color: days[i].isToday
                            ? primary
                            : AppColorRoles.textMuted(isDark),
                        fontWeight: days[i].isToday
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surfaceLight,
              getTooltipItems: (spots) => spots.map((s) {
                return LineTooltipItem(
                  '${s.y.toInt()} XP',
                  TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              }).toList(),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              curveSmoothness: 0.35,
              color: primary,
              barWidth: 2.5,
              dotData: FlDotData(
                show: true,
                getDotPainter: (spot, percent, bar, index) {
                  final isToday = days[index].isToday;
                  return FlDotCirclePainter(
                    radius: isToday ? 5 : 3,
                    color: isToday ? primary : AppColors.surfaceLight,
                    strokeWidth: 2,
                    strokeColor: primary,
                  );
                },
              ),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    primary.withValues(alpha: 0.22),
                    primary.withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ],
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

/// 7-day lessons completed bar chart.
class LessonsBarChart extends StatelessWidget {
  final WeeklyProgressEntity weeklyProgress;

  const LessonsBarChart({super.key, required this.weeklyProgress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = weeklyProgress.weekProgress;

    if (days.isEmpty || weeklyProgress.totalLessons == 0) {
      return _EmptyChart(isDark: isDark);
    }

    final primary = AppColorRoles.primary(isDark);
    final maxLessons = days
        .map((d) => d.lessonsCompleted)
        .reduce((a, b) => a > b ? a : b);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          minY: 0,
          maxY: (maxLessons + 2).toDouble(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: 1,
            getDrawingHorizontalLine: (_) => FlLine(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.07)
                  : Colors.black.withValues(alpha: 0.06),
              strokeWidth: 1,
            ),
          ),
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
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= days.length) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      days[i].day,
                      style: TextStyle(
                        fontSize: 10,
                        color: days[i].isToday
                            ? primary
                            : AppColorRoles.textMuted(isDark),
                        fontWeight: days[i].isToday
                            ? FontWeight.w700
                            : FontWeight.normal,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => isDark
                  ? AppColors.surfaceDarkElevated
                  : AppColors.surfaceLight,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final count = rod.toY.toInt();
                return BarTooltipItem(
                  '$count lesson${count != 1 ? 's' : ''}',
                  TextStyle(
                    color: primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                );
              },
            ),
          ),
          barGroups: days.asMap().entries.map((e) {
            final isToday = e.value.isToday;
            final count = e.value.lessonsCompleted.toDouble();
            return BarChartGroupData(
              x: e.key,
              barRods: [
                BarChartRodData(
                  toY: count,
                  width: 18,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(6),
                  ),
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: isToday
                        ? AppColorRoles.primaryGradient(isDark)
                        : [
                            primary.withValues(alpha: 0.35),
                            primary.withValues(alpha: 0.55),
                          ],
                  ),
                ),
              ],
            );
          }).toList(),
        ),
        duration: const Duration(milliseconds: 400),
      ),
    );
  }
}

/// 7-day activity heatmap row.
class WeekActivityHeatmap extends StatelessWidget {
  final WeeklyProgressEntity weeklyProgress;

  const WeekActivityHeatmap({super.key, required this.weeklyProgress});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final days = weeklyProgress.weekProgress;
    final primary = AppColorRoles.primary(isDark);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: days.map((day) {
        final intensity = day.progressPercentage;
        final hasActivity = day.hasActivity;

        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 40,
                  decoration: BoxDecoration(
                    color: hasActivity
                        ? primary.withValues(
                            alpha: (0.2 + intensity * 0.7).clamp(0.2, 0.9),
                          )
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.07)
                              : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(8),
                    border: day.isToday
                        ? Border.all(color: primary, width: 2)
                        : null,
                  ),
                  child: day.goalMet
                      ? Icon(Icons.check_rounded, size: 14, color: primary)
                      : null,
                ),
                const SizedBox(height: 4),
                Text(
                  day.day.substring(0, 1),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: day.isToday
                        ? FontWeight.w700
                        : FontWeight.normal,
                    color: day.isToday
                        ? primary
                        : AppColorRoles.textMuted(isDark),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _EmptyChart extends StatelessWidget {
  final bool isDark;
  const _EmptyChart({required this.isDark});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          'Start learning to see your progress chart!',
          style: TextStyle(
            color: AppColorRoles.textMuted(isDark),
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
