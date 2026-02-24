import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Progressive hangman drawing using CustomPainter.
///
/// Renders 0–6 body parts based on [wrongGuesses].
/// Parts order: gallows → head → body → left arm → right arm → legs (both drawn together).
class HangmanFigure extends StatelessWidget {
  final int wrongGuesses;

  const HangmanFigure({super.key, required this.wrongGuesses});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 200,
      child: CustomPaint(
        painter: _HangmanPainter(wrongGuesses: wrongGuesses.clamp(0, 6)),
      ),
    );
  }
}

class _HangmanPainter extends CustomPainter {
  final int wrongGuesses;

  _HangmanPainter({required this.wrongGuesses});

  @override
  void paint(Canvas canvas, Size size) {
    final gallowsPaint = Paint()
      ..color = AppColors.textDark
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final bodyPaint = Paint()
      ..color = AppColors.primary
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    // Always draw gallows
    _drawGallows(canvas, size, gallowsPaint);

    // Head
    if (wrongGuesses >= 1) _drawHead(canvas, size, bodyPaint);
    // Body
    if (wrongGuesses >= 2) _drawBody(canvas, size, bodyPaint);
    // Left arm
    if (wrongGuesses >= 3) _drawLeftArm(canvas, size, bodyPaint);
    // Right arm
    if (wrongGuesses >= 4) _drawRightArm(canvas, size, bodyPaint);
    // Left leg
    if (wrongGuesses >= 5) _drawLeftLeg(canvas, size, bodyPaint);
    // Right leg
    if (wrongGuesses >= 6) _drawRightLeg(canvas, size, bodyPaint);
  }

  void _drawGallows(Canvas canvas, Size size, Paint paint) {
    // Base
    canvas.drawLine(
      Offset(10, size.height - 10),
      Offset(size.width - 10, size.height - 10),
      paint,
    );
    // Vertical pole
    canvas.drawLine(
      Offset(size.width * 0.25, size.height - 10),
      Offset(size.width * 0.25, 10),
      paint,
    );
    // Horizontal beam
    canvas.drawLine(
      Offset(size.width * 0.25, 10),
      Offset(size.width * 0.65, 10),
      paint,
    );
    // Rope
    canvas.drawLine(
      Offset(size.width * 0.65, 10),
      Offset(size.width * 0.65, 38),
      paint,
    );
  }

  void _drawHead(Canvas canvas, Size size, Paint paint) {
    canvas.drawCircle(Offset(size.width * 0.65, 52), 14, paint);
  }

  void _drawBody(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.65, 66),
      Offset(size.width * 0.65, 120),
      paint,
    );
  }

  void _drawLeftArm(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.65, 78),
      Offset(size.width * 0.65 - 28, 100),
      paint,
    );
  }

  void _drawRightArm(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.65, 78),
      Offset(size.width * 0.65 + 28, 100),
      paint,
    );
  }

  void _drawLeftLeg(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.65, 120),
      Offset(size.width * 0.65 - 24, size.height - 30),
      paint,
    );
  }

  void _drawRightLeg(Canvas canvas, Size size, Paint paint) {
    canvas.drawLine(
      Offset(size.width * 0.65, 120),
      Offset(size.width * 0.65 + 24, size.height - 30),
      paint,
    );
  }

  @override
  bool shouldRepaint(_HangmanPainter old) => old.wrongGuesses != wrongGuesses;
}
