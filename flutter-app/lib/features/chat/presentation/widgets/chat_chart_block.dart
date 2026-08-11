import 'dart:convert';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Intercepts fenced ```chart code blocks in AI chat messages and renders
/// them as an fl_chart widget instead of literal code text.
///
/// Expected JSON spec inside the fence:
/// `{"type":"bar"|"line"|"pie","title":"optional","labels":["A","B"],
///   "series":[{"name":"...","values":[1,2]}]}`
class ChatChartElementBuilder extends MarkdownElementBuilder {
  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    final lang = element.attributes['class'] ?? '';
    if (!lang.contains('language-chart')) return null;
    return _ChatChartCard(rawSpec: element.textContent);
  }
}

class _ChartSeries {
  final String name;
  final List<double> values;
  const _ChartSeries({required this.name, required this.values});
}

const List<Color> _seriesPalette = [
  AppColors.primary,
  AppColors.accentMint,
  AppColors.accentYellow,
  AppColors.purple,
  AppColors.orange,
];

class _ChatChartCard extends StatelessWidget {
  final String rawSpec;
  const _ChatChartCard({required this.rawSpec});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Map<String, dynamic>? spec;
    try {
      final decoded = jsonDecode(rawSpec);
      if (decoded is Map<String, dynamic>) spec = decoded;
    } catch (_) {
      spec = null;
    }
    if (spec == null) return const SizedBox.shrink();

    final type = (spec['type'] as String? ?? 'bar').toLowerCase();
    final labels =
        (spec['labels'] as List?)?.map((e) => e.toString()).toList() ??
        const <String>[];
    final series = <_ChartSeries>[
      for (final s in (spec['series'] as List? ?? const []))
        if (s is Map)
          _ChartSeries(
            name: s['name']?.toString() ?? '',
            values: [
              for (final v in (s['values'] as List? ?? const []))
                if (v is num) v.toDouble(),
            ],
          ),
    ];
    if (labels.isEmpty || series.isEmpty || series.first.values.isEmpty) {
      return const SizedBox.shrink();
    }

    final title = spec['title'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.fromLTRB(14, 12, 16, 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkCard : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.grey200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColorRoles.textSecondary(isDark),
                ),
              ),
            ),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: switch (type) {
              'pie' => _PieChartView(labels: labels, series: series.first),
              'line' => _LineChartView(labels: labels, series: series),
              _ => _BarChartView(labels: labels, series: series),
            },
          ),
          const SizedBox(height: 8),
          _Legend(
            isDark: isDark,
            entries: type == 'pie'
                ? [
                    for (var i = 0; i < labels.length; i++)
                      (label: labels[i], color: _seriesPalette[i % _seriesPalette.length]),
                  ]
                : [
                    for (var i = 0; i < series.length; i++)
                      (label: series[i].name, color: _seriesPalette[i % _seriesPalette.length]),
                  ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  final bool isDark;
  final List<({String label, Color color})> entries;

  const _Legend({required this.isDark, required this.entries});

  @override
  Widget build(BuildContext context) {
    final visible = entries.where((e) => e.label.isNotEmpty).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: visible.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: e.color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 4),
            Text(
              e.label,
              style: TextStyle(
                fontSize: 11,
                color: AppColorRoles.textSecondary(isDark),
              ),
            ),
          ],
        );
      }).toList(),
    );
  }
}

class _BarChartView extends StatelessWidget {
  final List<String> labels;
  final List<_ChartSeries> series;
  const _BarChartView({required this.labels, required this.series});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxY = series
        .expand((s) => s.values)
        .fold<double>(0, (a, b) => b > a ? b : a);

    return BarChart(
      BarChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColorRoles.textMuted(isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < labels.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                for (var s = 0; s < series.length; s++)
                  BarChartRodData(
                    toY: i < series[s].values.length ? series[s].values[i] : 0,
                    width: series.length > 1 ? 8 : 16,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                    color: _seriesPalette[s % _seriesPalette.length],
                  ),
              ],
            ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

class _LineChartView extends StatelessWidget {
  final List<String> labels;
  final List<_ChartSeries> series;
  const _LineChartView({required this.labels, required this.series});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final maxY = series
        .expand((s) => s.values)
        .fold<double>(0, (a, b) => b > a ? b : a);

    return LineChart(
      LineChartData(
        minY: 0,
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) => FlLine(
            color: isDark
                ? Colors.white.withValues(alpha: 0.07)
                : Colors.black.withValues(alpha: 0.06),
            strokeWidth: 1,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 24,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= labels.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: AppColorRoles.textMuted(isDark),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        lineBarsData: [
          for (var s = 0; s < series.length; s++)
            LineChartBarData(
              spots: [
                for (var i = 0; i < series[s].values.length; i++)
                  FlSpot(i.toDouble(), series[s].values[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.3,
              color: _seriesPalette[s % _seriesPalette.length],
              barWidth: 2.5,
              dotData: const FlDotData(show: true),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}

class _PieChartView extends StatelessWidget {
  final List<String> labels;
  final _ChartSeries series;
  const _PieChartView({required this.labels, required this.series});

  @override
  Widget build(BuildContext context) {
    final total = series.values.fold<double>(0, (a, b) => a + b);
    if (total <= 0) return const SizedBox.shrink();

    return PieChart(
      PieChartData(
        sectionsSpace: 2,
        centerSpaceRadius: 32,
        sections: [
          for (var i = 0; i < labels.length && i < series.values.length; i++)
            PieChartSectionData(
              value: series.values[i],
              color: _seriesPalette[i % _seriesPalette.length],
              title: '${(series.values[i] / total * 100).round()}%',
              radius: 48,
              titleStyle: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
        ],
      ),
      duration: const Duration(milliseconds: 300),
    );
  }
}
