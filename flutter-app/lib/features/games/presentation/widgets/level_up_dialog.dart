import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';

/// Full-screen level-up celebration inspired by the Cyan Whisper prototype.
class LevelUpDialog extends StatefulWidget {
  final int newLevel;
  final int xpAwarded;

  const LevelUpDialog({
    super.key,
    required this.newLevel,
    required this.xpAwarded,
  });

  /// Show the level-up celebration as a modal flow.
  static Future<void> show(
    BuildContext context, {
    required int newLevel,
    required int xpAwarded,
  }) {
    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'games.levelUpTitle'.tr(),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) =>
          LevelUpDialog(newLevel: newLevel, xpAwarded: xpAwarded),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
          reverseCurve: Curves.easeInCubic,
        );
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  State<LevelUpDialog> createState() => _LevelUpDialogState();
}

class _LevelUpDialogState extends State<LevelUpDialog>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _progressController;
  late final AnimationController _orbitController;
  late final Animation<double> _heroScale;
  late final Animation<double> _contentFade;

  static const int _displayXpGoal = 1000;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();

    _heroScale = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.05, 0.72, curve: Curves.elasticOut),
    );
    _contentFade = CurvedAnimation(
      parent: _introController,
      curve: const Interval(0.42, 1, curve: Curves.easeOutCubic),
    );

    _introController.forward();
    Future<void>.delayed(const Duration(milliseconds: 520), () {
      if (mounted) _progressController.forward();
    });
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _progressController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = _LevelUpPalette.resolve(isDark);
    final xpForDisplay = math.max(0, widget.xpAwarded);
    final progress = math.min(1.0, xpForDisplay / _displayXpGoal);
    final nextLevel = widget.newLevel + 1;

    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 720;
            return Container(
              width: double.infinity,
              height: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: palette.backgroundGradient,
                ),
              ),
              child: Stack(
                children: [
                  _AmbientBackground(palette: palette),
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: LottieAnimationWidget(
                        animation: LottieAnimation.confetti,
                        fit: BoxFit.cover,
                        repeat: false,
                      ),
                    ),
                  ),
                  Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 430),
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 14 : 28,
                          24,
                          compact ? 18 : 28,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _HeaderCopy(palette: palette, compact: compact),
                            SizedBox(height: compact ? 16 : 24),
                            ScaleTransition(
                              scale: _heroScale,
                              child: _LevelHero(
                                level: widget.newLevel,
                                palette: palette,
                                orbitController: _orbitController,
                                compact: compact,
                              ),
                            ),
                            SizedBox(height: compact ? 18 : 28),
                            FadeTransition(
                              opacity: _contentFade,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.06),
                                  end: Offset.zero,
                                ).animate(_contentFade),
                                child: Column(
                                  children: [
                                    _ProgressPanel(
                                      palette: palette,
                                      progressController: _progressController,
                                      progress: progress,
                                      xpAwarded: xpForDisplay,
                                      xpGoal: _displayXpGoal,
                                      nextLevel: nextLevel,
                                    ),
                                    SizedBox(height: compact ? 18 : 24),
                                    _ContinueButton(
                                      palette: palette,
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _LevelUpPalette {
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color surface;
  final Color surfaceHigh;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color primarySoft;
  final Color primaryDeep;
  final Color gold;
  final Color goldDeep;
  final Color outline;
  final Color shadow;

  const _LevelUpPalette({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.surfaceHigh,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.primarySoft,
    required this.primaryDeep,
    required this.gold,
    required this.goldDeep,
    required this.outline,
    required this.shadow,
  });

  List<Color> get backgroundGradient => [backgroundTop, backgroundBottom];

  static _LevelUpPalette resolve(bool isDark) {
    if (isDark) {
      return const _LevelUpPalette(
        backgroundTop: Color(0xFF07191E),
        backgroundBottom: Color(0xFF15232C),
        surface: Color(0xE61D2C35),
        surfaceHigh: Color(0xFF243743),
        onSurface: AppColors.textOnDarkPrimary,
        onSurfaceVariant: AppColors.textOnDarkSecondary,
        primary: Color(0xFF5DF4F2),
        primarySoft: Color(0x3330E8E8),
        primaryDeep: Color(0xFF0FA3A7),
        gold: Color(0xFFFFD644),
        goldDeep: Color(0xFFC98A13),
        outline: Color(0x2EEFFDFF),
        shadow: Color(0x66030C10),
      );
    }
    return const _LevelUpPalette(
      backgroundTop: Color(0xFFE9FBFA),
      backgroundBottom: Color(0xFFF9F7EF),
      surface: Color(0xEAFFFFFF),
      surfaceHigh: Color(0xFFF5FBFA),
      onSurface: AppColors.textDark,
      onSurfaceVariant: AppColors.textSlate,
      primary: Color(0xFF18CACA),
      primarySoft: Color(0x2630E8E8),
      primaryDeep: Color(0xFF007D80),
      gold: AppColors.accentYellow,
      goldDeep: Color(0xFF8A6500),
      outline: Color(0x190F1717),
      shadow: Color(0x2630E8E8),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  final _LevelUpPalette palette;

  const _AmbientBackground({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.72),
            radius: 0.86,
            colors: [
              palette.primary.withValues(alpha: 0.2),
              palette.primary.withValues(alpha: 0.06),
              Colors.transparent,
            ],
            stops: const [0, 0.48, 1],
          ),
        ),
        child: CustomPaint(painter: _SubtleGridPainter(palette.outline)),
      ),
    );
  }
}

class _SubtleGridPainter extends CustomPainter {
  final Color color;

  const _SubtleGridPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 0.6;
    const gap = 24.0;
    for (double x = 0; x <= size.width; x += gap) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += gap) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SubtleGridPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _HeaderCopy extends StatelessWidget {
  final _LevelUpPalette palette;
  final bool compact;

  const _HeaderCopy({required this.palette, required this.compact});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'games.levelUpTitle'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
            color: palette.primary,
            fontSize: compact ? 34 : 42,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.2,
            shadows: [
              Shadow(
                color: palette.primary.withValues(alpha: 0.22),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'games.levelUpSubtitle'.tr(),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            color: palette.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _LevelHero extends StatelessWidget {
  final int level;
  final _LevelUpPalette palette;
  final AnimationController orbitController;
  final bool compact;

  const _LevelHero({
    required this.level,
    required this.palette,
    required this.orbitController,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final heroSize = compact ? 230.0 : 276.0;
    return SizedBox(
      width: heroSize,
      height: heroSize,
      child: Stack(
        alignment: Alignment.center,
        children: [
          LottieAnimationWidget(
            animation: LottieAnimation.starBurst,
            width: heroSize,
            height: heroSize,
            repeat: false,
          ),
          RotationTransition(
            turns: orbitController,
            child: LottieAnimationWidget(
              animation: LottieAnimation.levelUpOrbit,
              width: heroSize * 0.94,
              height: heroSize * 0.94,
              repeat: true,
            ),
          ),
          CustomPaint(
            size: Size.square(heroSize * 0.72),
            painter: _StarBadgePainter(
              fill: palette.gold,
              accent: palette.primary,
              shadow: palette.shadow,
            ),
          ),
          Container(
            width: heroSize * 0.48,
            height: heroSize * 0.48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: palette.surface,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: palette.shadow,
                  blurRadius: 32,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  'games.levelLabel'.tr(),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: palette.onSurfaceVariant,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.4,
                  ),
                ),
                Text(
                  '$level',
                  style: Theme.of(context).textTheme.displayMedium?.copyWith(
                    color: palette.primary,
                    height: 0.95,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StarBadgePainter extends CustomPainter {
  final Color fill;
  final Color accent;
  final Color shadow;

  const _StarBadgePainter({
    required this.fill,
    required this.accent,
    required this.shadow,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outer = size.shortestSide / 2;
    final inner = outer * 0.46;
    final path = Path();

    for (var i = 0; i < 10; i++) {
      final radius = i.isEven ? outer : inner;
      final angle = -math.pi / 2 + i * math.pi / 5;
      final point = center + Offset(math.cos(angle), math.sin(angle)) * radius;
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    path.close();

    canvas.drawShadow(path, shadow, 18, true);
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [fill, const Color(0xFFFFF4AE), fill.withValues(alpha: 0.78)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent.withValues(alpha: 0.38),
    );
  }

  @override
  bool shouldRepaint(covariant _StarBadgePainter oldDelegate) =>
      oldDelegate.fill != fill ||
      oldDelegate.accent != accent ||
      oldDelegate.shadow != shadow;
}

class _ProgressPanel extends StatelessWidget {
  final _LevelUpPalette palette;
  final AnimationController progressController;
  final double progress;
  final int xpAwarded;
  final int xpGoal;
  final int nextLevel;

  const _ProgressPanel({
    required this.palette,
    required this.progressController,
    required this.progress,
    required this.xpAwarded,
    required this.xpGoal,
    required this.nextLevel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 34,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _RoundIcon(
                icon: Icons.bolt_rounded,
                color: palette.primary,
                background: palette.primarySoft,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'games.sessionScore'.tr(),
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: palette.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'games.xpEarned'.tr(namedArgs: {'xp': '$xpAwarded'}),
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(
                            color: palette.onSurface,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.4,
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: Text(
                  'games.progressToLevel'.tr(
                    namedArgs: {'level': '$nextLevel'},
                  ),
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: palette.onSurface,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                'games.xpProgressShort'.tr(
                  namedArgs: {
                    'current': '${math.min(xpAwarded, xpGoal)}',
                    'total': '$xpGoal',
                  },
                ),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: palette.primary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          AnimatedBuilder(
            animation: progressController,
            builder: (context, child) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  minHeight: 12,
                  value: progress * progressController.value,
                  backgroundColor: palette.onSurface.withValues(alpha: 0.1),
                  valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          Divider(color: palette.outline),
          const SizedBox(height: 16),
          Text(
            'games.newUnlocks'.tr(),
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: palette.onSurfaceVariant,
              fontWeight: FontWeight.w900,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _UnlockItem(
                  palette: palette,
                  icon: Icons.inventory_2_outlined,
                  titleKey: 'games.unlockGoldenChest',
                  color: palette.goldDeep,
                ),
              ),
              Expanded(
                child: _UnlockItem(
                  palette: palette,
                  icon: Icons.diamond_outlined,
                  titleKey: 'games.unlockGems',
                  color: palette.primary,
                ),
              ),
              Expanded(
                child: _UnlockItem(
                  palette: palette,
                  icon: Icons.flash_on_rounded,
                  titleKey: 'games.unlockXpBooster',
                  color: palette.primaryDeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color background;

  const _RoundIcon({
    required this.icon,
    required this.color,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 54,
      height: 54,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, color: color, size: 30),
    );
  }
}

class _UnlockItem extends StatelessWidget {
  final _LevelUpPalette palette;
  final IconData icon;
  final String titleKey;
  final Color color;

  const _UnlockItem({
    required this.palette,
    required this.icon,
    required this.titleKey,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 62,
          height: 62,
          decoration: BoxDecoration(
            color: palette.surfaceHigh,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: palette.shadow.withValues(alpha: 0.55),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Icon(icon, color: color, size: 32),
        ),
        const SizedBox(height: 10),
        Text(
          titleKey.tr(),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: palette.onSurfaceVariant,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final _LevelUpPalette palette;
  final VoidCallback onPressed;

  const _ContinueButton({required this.palette, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_forward_rounded),
        label: Text('games.continueJourney'.tr()),
        style:
            ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(58),
              backgroundColor: palette.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shadowColor: Colors.transparent,
              textStyle: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 0.1,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ).copyWith(
              overlayColor: WidgetStatePropertyAll(
                Colors.white.withValues(alpha: 0.12),
              ),
            ),
      ),
    );
  }
}
