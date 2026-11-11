import 'dart:math';

import 'package:flutter/material.dart';

/// Soft pastel gradient with one of five decorative motifs, drawn in the
/// card's own accent so dark text stays readable on top.
class CardArtPainter extends CustomPainter {
  const CardArtPainter({
    required this.accent,
    required this.base,
    required this.motif,
    required this.isDark,
  });

  final Color accent;
  final Color base;
  final int motif;
  final bool isDark;

  static const motifCount = 5;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.30 : 0.20),
              base,
            ),
            Color.alphaBlend(
              accent.withValues(alpha: isDark ? 0.10 : 0.05),
              base,
            ),
          ],
        ).createShader(rect),
    );

    switch (motif % motifCount) {
      case 0:
        _bubbles(canvas, size);
      case 1:
        _waves(canvas, size);
      case 2:
        _sparkles(canvas, size);
      case 3:
        _rays(canvas, size);
      default:
        _dots(canvas, size);
    }
  }

  Paint _fill(double alpha) =>
      Paint()..color = accent.withValues(alpha: isDark ? alpha * 1.4 : alpha);

  void _bubbles(Canvas canvas, Size s) {
    canvas.drawCircle(
      Offset(s.width * 0.95, s.height * 0.05),
      s.height * 0.5,
      _fill(0.16),
    );
    canvas.drawCircle(
      Offset(s.width * 0.70, s.height * -0.02),
      s.height * 0.28,
      _fill(0.12),
    );
    canvas.drawCircle(
      Offset(s.width * 1.02, s.height * 0.85),
      s.height * 0.3,
      _fill(0.12),
    );
    canvas.drawCircle(
      Offset(s.width * 0.82, s.height * 0.38),
      s.height * 0.1,
      Paint()
        ..color = accent.withValues(alpha: 0.30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _waves(Canvas canvas, Size s) {
    void wave(double y, double amp, double phase, Paint paint) {
      final path = Path()..moveTo(0, s.height);
      for (var x = 0.0; x <= s.width; x += 4) {
        path.lineTo(x, y + sin(x / s.width * 2 * pi + phase) * amp);
      }
      path
        ..lineTo(s.width, s.height)
        ..close();
      canvas.drawPath(path, paint);
    }

    wave(s.height * 0.70, s.height * 0.07, 0, _fill(0.12));
    wave(s.height * 0.82, s.height * 0.06, 2, _fill(0.18));
    canvas.drawCircle(
      Offset(s.width * 0.9, s.height * 0.14),
      s.height * 0.12,
      _fill(0.2),
    );
  }

  void _star(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (var i = 0; i < 8; i++) {
      final radius = i.isEven ? r : r * 0.3;
      final a = -pi / 2 + i * pi / 4;
      final p = c + Offset(cos(a), sin(a)) * radius;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), paint);
  }

  void _sparkles(Canvas canvas, Size s) {
    _star(
      canvas,
      Offset(s.width * 0.86, s.height * 0.24),
      s.height * 0.2,
      _fill(0.28),
    );
    _star(
      canvas,
      Offset(s.width * 0.66, s.height * 0.1),
      s.height * 0.09,
      _fill(0.22),
    );
    _star(
      canvas,
      Offset(s.width * 0.93, s.height * 0.62),
      s.height * 0.1,
      _fill(0.2),
    );
    canvas.drawCircle(Offset(s.width * 0.74, s.height * 0.5), 3, _fill(0.3));
    canvas.drawCircle(Offset(s.width * 0.55, s.height * 0.3), 2, _fill(0.25));
  }

  void _rays(Canvas canvas, Size s) {
    final origin = Offset(s.width, 0);
    final radius = s.width * 1.5;
    const rays = 7;
    for (var i = 0; i < rays; i += 2) {
      final start = pi / 2 + i * (pi / 2) / rays;
      canvas.drawPath(
        Path()
          ..moveTo(origin.dx, origin.dy)
          ..arcTo(
            Rect.fromCircle(center: origin, radius: radius),
            start,
            (pi / 2) / rays,
            false,
          )
          ..close(),
        _fill(0.14),
      );
    }
    canvas.drawCircle(origin, s.height * 0.22, _fill(0.2));
  }

  void _dots(Canvas canvas, Size s) {
    const step = 14.0;
    for (var x = s.width * 0.55; x < s.width; x += step) {
      for (var y = 8.0; y < s.height * 0.55; y += step) {
        final fade = 1 - (x - s.width * 0.55) / (s.width * 0.45) * 0.5;
        canvas.drawCircle(Offset(x, y), 1.8, _fill(0.28 * fade));
      }
    }
    canvas.drawCircle(
      Offset(s.width * 0.05, s.height * 1.0),
      s.height * 0.42,
      Paint()
        ..color = accent.withValues(alpha: isDark ? 0.25 : 0.14)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 12,
    );
  }

  @override
  bool shouldRepaint(CardArtPainter old) =>
      old.accent != accent ||
      old.base != base ||
      old.motif != motif ||
      old.isDark != isDark;
}
