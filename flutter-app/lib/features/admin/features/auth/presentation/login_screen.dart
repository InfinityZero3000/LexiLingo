import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/features/admin/shared/admin_exit_scope.dart';
import '../../../core/constants/app_colors.dart';
import 'auth_provider.dart';

class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  void _closeAdminPanel(BuildContext context) {
    final exitScope = AdminExitScope.maybeOf(context);
    if (exitScope != null) {
      exitScope.onExit();
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _signInWithGoogle(BuildContext context) async {
    final auth = context.read<AuthProvider>();
    final ok = await auth.loginWithGoogle();
    if (ok && context.mounted) {
      context.go('/dashboard');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final isLoading = auth.state == AuthState.loading;

    return Scaffold(
      backgroundColor: const Color(0xFFD4E9FF),
      body: DecoratedBox(
        key: const Key('admin-login-background'),
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.8),
            radius: 1.4,
            colors: [Color(0xFFFFF0E6), Color(0xFFE1F2FF), Color(0xFFD4E9FF)],
            stops: [0.0, 0.45, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, viewport) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: viewport.maxHeight),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 18,
                    ),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 460),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextButton.icon(
                              onPressed: () => _closeAdminPanel(context),
                              icon: const Icon(
                                Icons.arrow_back_rounded,
                                size: 18,
                              ),
                              label: const Text('Back to LexiLingo'),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4,
                                  vertical: 8,
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            // Brand
                            Row(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFFFF4D00),
                                        Color(0xFFFF6F2A),
                                      ],
                                    ),
                                    borderRadius: BorderRadius.circular(14),
                                    boxShadow: const [
                                      BoxShadow(
                                        color: Color(0x59FF4D00),
                                        blurRadius: 16,
                                        offset: Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: const Icon(
                                    Icons.language,
                                    color: Colors.white,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      ConstrainedBox(
                                        constraints: const BoxConstraints(
                                          maxWidth: 220,
                                        ),
                                        child: Image.asset(
                                          'assets/out-app/lexilingo-logo.png',
                                          height: 30,
                                          fit: BoxFit.contain,
                                          alignment: Alignment.centerLeft,
                                        ),
                                      ),
                                      Text(
                                        'ADMIN CONSOLE',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w600,
                                          letterSpacing: 0.18,
                                          color: AppColors.onSurfaceMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 56),
                            Text(
                              'Admin Login',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                color: AppColors.onSurface,
                                letterSpacing: -0.02,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Đăng nhập bằng tài khoản Google admin của bạn.',
                              style: GoogleFonts.spaceGrotesk(
                                fontSize: 15,
                                color: AppColors.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 48),
                            // Google Sign-In button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: ElevatedButton(
                                onPressed: isLoading
                                    ? null
                                    : () => _signInWithGoogle(context),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.surface,
                                  foregroundColor: AppColors.onSurface,
                                  elevation: 2,
                                  shadowColor: const Color(0x1A0A3256),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    side: const BorderSide(
                                      color: AppColors.outline,
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppColors.primary,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _GoogleLogo(),
                                          const SizedBox(width: 12),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'Đăng nhập với Google',
                                                style: GoogleFonts.spaceGrotesk(
                                                  fontSize: 15,
                                                  fontWeight: FontWeight.w600,
                                                  color: AppColors.onSurface,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            if (auth.error != null) ...[
                              const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.errorContainer,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.error_outline,
                                      color: AppColors.error,
                                      size: 16,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        auth.error!,
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 13,
                                          color: AppColors.error,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 48),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: AppColors.outline),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.shield_outlined,
                                        size: 14,
                                        color: AppColors.onSurfaceMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'Google OAuth · Admin only · Secured',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          color: AppColors.onSurfaceMuted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _GoogleLogo extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 22,
      height: 22,
      child: CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2;

    // Blue arc (top-right → bottom-left)
    final bluePaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.round;

    // Red arc
    final redPaint = Paint()
      ..color = const Color(0xFFEA4335)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.round;

    // Yellow arc
    final yellowPaint = Paint()
      ..color = const Color(0xFFFBBC05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.round;

    // Green arc
    final greenPaint = Paint()
      ..color = const Color(0xFF34A853)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.round;

    final arcR = r * 0.72;
    final rect = Rect.fromCircle(center: Offset(cx, cy), radius: arcR);

    canvas.drawArc(rect, -0.52, 1.57, false, bluePaint); // top-right (blue)
    canvas.drawArc(rect, 1.05, 1.57, false, redPaint); // bottom-right (red)
    canvas.drawArc(
      rect,
      2.62,
      1.57,
      false,
      yellowPaint,
    ); // bottom-left (yellow)
    canvas.drawArc(rect, 4.19, 1.57, false, greenPaint); // top-left (green)

    // Horizontal bar (right side)
    final barPaint = Paint()
      ..color = const Color(0xFF4285F4)
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.18
      ..strokeCap = StrokeCap.round;

    canvas.drawLine(
      Offset(cx, cy),
      Offset(cx + arcR + size.width * 0.09, cy),
      barPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
