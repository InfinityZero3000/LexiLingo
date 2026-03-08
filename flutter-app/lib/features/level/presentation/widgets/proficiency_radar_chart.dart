import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Maps 6 backend skills to 5 display dimensions for radar chart
class ProficiencyDimensionMapper {
  static const List<String> dimensionLabels = [
    'Pronunciation',
    'Vocabulary',
    'Fluency',
    'Grammar',
    'Intonation',
  ];

  /// Map backend skill scores to 5 display dimensions
  static Map<String, double> mapToDisplayDimensions(
    Map<String, double> skillScores,
  ) {
    final speaking = skillScores['speaking'] ?? 0;
    final listening = skillScores['listening'] ?? 0;
    final vocabulary = skillScores['vocabulary'] ?? 0;
    final grammar = skillScores['grammar'] ?? 0;
    final reading = skillScores['reading'] ?? 0;
    final writing = skillScores['writing'] ?? 0;

    return {
      'Pronunciation': speaking,
      'Vocabulary': vocabulary * 0.7 + reading * 0.3,
      'Fluency': speaking * 0.6 + listening * 0.4,
      'Grammar': grammar * 0.8 + writing * 0.2,
      'Intonation': speaking * 0.5 + listening * 0.5,
    };
  }
}

/// Proficiency radar/spider chart using CustomPainter
class ProficiencyRadarChart extends StatefulWidget {
  final Map<String, double> scores;
  final double size;
  final Color fillColor;
  final Color strokeColor;
  final Color gridColor;
  final Color labelColor;
  final bool animate;

  const ProficiencyRadarChart({
    super.key,
    required this.scores,
    this.size = 220,
    this.fillColor = const Color(0x336366F1),
    this.strokeColor = const Color(0xFF6366F1),
    this.gridColor = const Color(0xFFE2E8F0),
    this.labelColor = const Color(0xFF64748B),
    this.animate = true,
  });

  @override
  State<ProficiencyRadarChart> createState() => _ProficiencyRadarChartState();
}

class _ProficiencyRadarChartState extends State<ProficiencyRadarChart>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    if (widget.animate) {
      _controller.forward();
    } else {
      _controller.value = 1.0;
    }
  }

  @override
  void didUpdateWidget(covariant ProficiencyRadarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scores != widget.scores && widget.animate) {
      _controller.reset();
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveGridColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : widget.gridColor;
    final effectiveLabelColor = isDark ? Colors.grey[400]! : widget.labelColor;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Semantics(
          label: _buildAccessibilityLabel(),
          child: CustomPaint(
            size: Size(widget.size, widget.size),
            painter: _RadarChartPainter(
              scores: widget.scores,
              progress: _animation.value,
              fillColor: widget.fillColor,
              strokeColor: widget.strokeColor,
              gridColor: effectiveGridColor,
              labelColor: effectiveLabelColor,
            ),
          ),
        );
      },
    );
  }

  String _buildAccessibilityLabel() {
    final parts = widget.scores.entries
        .map((e) => '${e.key} ${(e.value * 100).toInt()}%')
        .join(', ');
    return 'Your proficiency: $parts';
  }
}

class _RadarChartPainter extends CustomPainter {
  final Map<String, double> scores;
  final double progress;
  final Color fillColor;
  final Color strokeColor;
  final Color gridColor;
  final Color labelColor;

  _RadarChartPainter({
    required this.scores,
    required this.progress,
    required this.fillColor,
    required this.strokeColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.34; // Leave room for labels
    final entries = scores.entries.toList();
    final count = entries.length;
    if (count < 3) return;

    final angleStep = 2 * math.pi / count;
    // Start from top (- pi/2)
    const startAngle = -math.pi / 2;

    // Draw grid rings
    _drawGridRings(canvas, center, radius, count, angleStep, startAngle);

    // Draw data polygon
    _drawDataPolygon(canvas, center, radius, entries, angleStep, startAngle);

    // Draw axis lines
    _drawAxisLines(canvas, center, radius, count, angleStep, startAngle);

    // Draw labels
    _drawLabels(canvas, center, radius, entries, angleStep, startAngle, size);

    // Draw data points
    _drawDataPoints(canvas, center, radius, entries, angleStep, startAngle);
  }

  void _drawGridRings(
    Canvas canvas,
    Offset center,
    double radius,
    int count,
    double angleStep,
    double startAngle,
  ) {
    final gridPaint = Paint()
      ..color = gridColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    // Draw 5 grid levels (20%, 40%, 60%, 80%, 100%)
    for (var level = 1; level <= 5; level++) {
      final r = radius * level / 5;
      final path = Path();
      for (var i = 0; i < count; i++) {
        final angle = startAngle + angleStep * i;
        final point = Offset(
          center.dx + r * math.cos(angle),
          center.dy + r * math.sin(angle),
        );
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      path.close();
      canvas.drawPath(path, gridPaint);
    }
  }

  void _drawAxisLines(
    Canvas canvas,
    Offset center,
    double radius,
    int count,
    double angleStep,
    double startAngle,
  ) {
    final axisPaint = Paint()
      ..color = gridColor.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    for (var i = 0; i < count; i++) {
      final angle = startAngle + angleStep * i;
      final end = Offset(
        center.dx + radius * math.cos(angle),
        center.dy + radius * math.sin(angle),
      );
      canvas.drawLine(center, end, axisPaint);
    }
  }

  void _drawDataPolygon(
    Canvas canvas,
    Offset center,
    double radius,
    List<MapEntry<String, double>> entries,
    double angleStep,
    double startAngle,
  ) {
    final fillPaint = Paint()
      ..color = fillColor
      ..style = PaintingStyle.fill;

    final strokePaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round;

    final path = Path();
    for (var i = 0; i < entries.length; i++) {
      final value = entries[i].value.clamp(0.0, 1.0) * progress;
      final angle = startAngle + angleStep * i;
      final r = radius * value;
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();
    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  void _drawDataPoints(
    Canvas canvas,
    Offset center,
    double radius,
    List<MapEntry<String, double>> entries,
    double angleStep,
    double startAngle,
  ) {
    final dotPaint = Paint()
      ..color = strokeColor
      ..style = PaintingStyle.fill;

    final dotBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    for (var i = 0; i < entries.length; i++) {
      final value = entries[i].value.clamp(0.0, 1.0) * progress;
      final angle = startAngle + angleStep * i;
      final r = radius * value;
      final point = Offset(
        center.dx + r * math.cos(angle),
        center.dy + r * math.sin(angle),
      );
      canvas.drawCircle(point, 5, dotBorderPaint);
      canvas.drawCircle(point, 3.5, dotPaint);
    }
  }

  void _drawLabels(
    Canvas canvas,
    Offset center,
    double radius,
    List<MapEntry<String, double>> entries,
    double angleStep,
    double startAngle,
    Size size,
  ) {
    for (var i = 0; i < entries.length; i++) {
      final angle = startAngle + angleStep * i;
      final labelRadius = radius + 24;
      final labelPos = Offset(
        center.dx + labelRadius * math.cos(angle),
        center.dy + labelRadius * math.sin(angle),
      );

      // Draw score value
      final scoreText = entries[i].value > 0
          ? '${(entries[i].value * 100 * progress).toInt()}'
          : '--';

      final scorePainter = TextPainter(
        text: TextSpan(
          text: scoreText,
          style: TextStyle(
            color: strokeColor,
            fontSize: 12,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Draw label name
      final labelPainter = TextPainter(
        text: TextSpan(
          text: entries[i].key,
          style: TextStyle(
            color: labelColor,
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      // Position labels
      double labelX = labelPos.dx - labelPainter.width / 2;
      double labelY = labelPos.dy - labelPainter.height / 2;
      double scoreX = labelPos.dx - scorePainter.width / 2;
      double scoreY = labelY - scorePainter.height - 2;

      // Adjust for top label
      if (i == 0) {
        scoreY = labelPos.dy - scorePainter.height - labelPainter.height - 4;
        labelY = labelPos.dy - labelPainter.height;
      }
      // Adjust for bottom labels
      if (angle > math.pi * 0.2 && angle < math.pi * 0.8) {
        labelY = labelPos.dy;
        scoreY = labelY - scorePainter.height - 2;
      }

      labelPainter.paint(canvas, Offset(labelX, labelY));
      scorePainter.paint(canvas, Offset(scoreX, scoreY));
    }
  }

  @override
  bool shouldRepaint(covariant _RadarChartPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.scores != scores ||
        oldDelegate.fillColor != fillColor;
  }
}
