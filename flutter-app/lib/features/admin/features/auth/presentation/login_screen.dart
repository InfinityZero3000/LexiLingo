import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/admin/shared/admin_exit_scope.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import 'auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart' show AppColors;
import 'package:lexilingo_app/core/theme/app_tokens.dart';

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
      backgroundColor: context.ac.primaryContainer,
      body: DecoratedBox(
        key: const Key('admin-login-background'),
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(-0.7, -0.8),
            radius: 1.4,
            colors: Theme.of(context).brightness == Brightness.dark
                ? [
                    AppColors.surfaceDarkElevated,
                    AppColors.surfaceDark,
                    context.ac.primaryContainer,
                  ]
                : [
                    AppColors.surfaceWarm,
                    AppColors.skyBackground,
                    context.ac.primaryContainer,
                  ],
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
                      horizontal: AppSpacing.xl,
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
                                foregroundColor: context.ac.onSurfaceVariant,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: AppSpacing.sm,
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
                                      colors: AppColors.primaryGradient,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.35,
                                        ),
                                        blurRadius: 16,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.language,
                                    color: AppColors.onGradient,
                                    size: 26,
                                  ),
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Image.asset(
                                        'assets/out-app/lexilingo-text.png',
                                        height: 36,
                                        fit: BoxFit.contain,
                                      ),
                                      Text(
                                        'adminUi.login.adminConsole'.tr(),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w600,
                                              letterSpacing: 0.18,
                                              color: context.ac.onSurfaceMuted,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 56),
                            Text(
                              'adminUi.login.adminLogin'.tr(),
                              style: Theme.of(context).textTheme.headlineLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: context.ac.onSurface,
                                    letterSpacing: -0.02,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.sm),
                            Text(
                              'adminUi.login.ngNhPBNg'.tr(),
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(
                                    color: context.ac.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 48),
                            // Google Sign-In button
                            SizedBox(
                              width: double.infinity,
                              height: 56,
                              child: FilledButton(
                                onPressed: isLoading
                                    ? null
                                    : () => _signInWithGoogle(context),
                                style: FilledButton.styleFrom(
                                  backgroundColor: context.ac.surface,
                                  foregroundColor: context.ac.onSurface,
                                  elevation: 2,
                                  shadowColor: AppColors.surfaceDarkInk
                                      .withValues(alpha: 0.1),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.md,
                                    ),
                                    side: BorderSide(
                                      color: context.ac.outline,
                                      width: 1.2,
                                    ),
                                  ),
                                ),
                                child: isLoading
                                    ? SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: context.ac.primary,
                                        ),
                                      )
                                    : Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          _GoogleLogo(),
                                          const SizedBox(width: AppSpacing.md),
                                          Flexible(
                                            child: FittedBox(
                                              fit: BoxFit.scaleDown,
                                              child: Text(
                                                'adminUi.login.ngNhPVI'.tr(),
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodyLarge
                                                    ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color:
                                                          context.ac.onSurface,
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                              ),
                            ),
                            if (auth.error != null) ...[
                              const SizedBox(height: AppSpacing.lg),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: context.ac.errorContainer,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: context.ac.error,
                                      size: 16,
                                    ),
                                    const SizedBox(width: AppSpacing.sm),
                                    Expanded(
                                      child: Text(
                                        auth.error!,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(color: context.ac.error),
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
                                  horizontal: AppSpacing.lg,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: context.ac.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                  border: Border.all(color: context.ac.outline),
                                ),
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.shield_outlined,
                                        size: 14,
                                        color: context.ac.onSurfaceMuted,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'adminUi.login.googleOauthAdminOnlySecured'
                                            .tr(),
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(
                                              color: context.ac.onSurfaceMuted,
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
