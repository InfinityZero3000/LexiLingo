import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

/// Full-screen Rank-up celebration inspired by LevelUpDialog.
class RankUpDialog extends StatefulWidget {
  final String newRank;
  final String oldRank;

  const RankUpDialog({super.key, required this.newRank, required this.oldRank});

  /// Show the rank-up celebration as a modal flow.
  static Future<void> show(
    BuildContext context, {
    required String newRank,
    required String oldRank,
  }) {
    // Prevent duplicated / overlapping dialogs if rank doesn't change
    if (newRank.toLowerCase() == oldRank.toLowerCase()) return Future.value();

    return showGeneralDialog(
      context: context,
      barrierDismissible: false,
      barrierLabel: 'Rank Up',
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) =>
          RankUpDialog(newRank: newRank, oldRank: oldRank),
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
  State<RankUpDialog> createState() => _RankUpDialogState();
}

class _RankUpDialogState extends State<RankUpDialog>
    with TickerProviderStateMixin {
  late final AnimationController _introController;
  late final AnimationController _orbitController;
  late final Animation<double> _heroScale;
  late final Animation<double> _contentFade;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 980),
    );
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
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
  }

  @override
  void dispose() {
    _orbitController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visualData = rankVisualDataFor(widget.newRank);
    final palette = _RankUpPalette.resolve(isDark, visualData.color);

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
                            _HeaderCopy(
                              palette: palette,
                              compact: compact,
                              rankName: visualData.name,
                            ),
                            SizedBox(height: compact ? 24 : 36),
                            ScaleTransition(
                              scale: _heroScale,
                              child: _RankHero(
                                rank: widget.newRank,
                                palette: palette,
                                orbitController: _orbitController,
                                compact: compact,
                                color: visualData.color,
                              ),
                            ),
                            SizedBox(height: compact ? 28 : 42),
                            FadeTransition(
                              opacity: _contentFade,
                              child: SlideTransition(
                                position: Tween<Offset>(
                                  begin: const Offset(0, 0.06),
                                  end: Offset.zero,
                                ).animate(_contentFade),
                                child: Column(
                                  children: [
                                    _RankUpMessage(
                                      palette: palette,
                                      oldRankName: rankDisplayNameFor(
                                        widget.oldRank,
                                      ),
                                      newRankName: rankDisplayNameFor(
                                        widget.newRank,
                                      ),
                                    ),
                                    SizedBox(height: compact ? 24 : 36),
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

class _RankUpPalette {
  final Color backgroundTop;
  final Color backgroundBottom;
  final Color surface;
  final Color onSurfaceVariant;
  final Color primary;
  final Color primarySoft;
  final Color outline;
  final Color shadow;

  const _RankUpPalette({
    required this.backgroundTop,
    required this.backgroundBottom,
    required this.surface,
    required this.onSurfaceVariant,
    required this.primary,
    required this.primarySoft,
    required this.outline,
    required this.shadow,
  });

  List<Color> get backgroundGradient => [backgroundTop, backgroundBottom];

  static _RankUpPalette resolve(bool isDark, Color rankColor) {
    if (isDark) {
      return _RankUpPalette(
        backgroundTop: const Color(0xFF111418),
        backgroundBottom: const Color(0xFF1A1D24),
        surface: const Color(0xE6242830),
        onSurfaceVariant: AppColors.textOnDarkSecondary,
        primary: rankColor,
        primarySoft: rankColor.withValues(alpha: 0.15),
        outline: const Color(0x19FFFFFF),
        shadow: const Color(0x66000000),
      );
    }
    return _RankUpPalette(
      backgroundTop: rankColor.withValues(alpha: 0.08),
      backgroundBottom: rankColor.withValues(alpha: 0.02),
      surface: const Color(0xEAFFFFFF),
      onSurfaceVariant: AppColors.textSlate,
      primary: rankColor,
      primarySoft: rankColor.withValues(alpha: 0.1),
      outline: const Color(0x19000000),
      shadow: rankColor.withValues(alpha: 0.2),
    );
  }
}

class _AmbientBackground extends StatelessWidget {
  final _RankUpPalette palette;

  const _AmbientBackground({required this.palette});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.6),
            radius: 0.9,
            colors: [
              palette.primary.withValues(alpha: 0.25),
              palette.primary.withValues(alpha: 0.08),
              Colors.transparent,
            ],
            stops: const [0, 0.5, 1],
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
    const gap = 32.0;
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
  final _RankUpPalette palette;
  final bool compact;
  final String rankName;

  const _HeaderCopy({
    required this.palette,
    required this.compact,
    required this.rankName,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          'Rank Up!',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.displayMedium?.copyWith(
            color: palette.primary,
            fontSize: compact ? 36 : 46,
            fontWeight: FontWeight.w900,
            letterSpacing: -1.0,
            shadows: [
              Shadow(
                color: palette.primary.withValues(alpha: 0.3),
                blurRadius: 24,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'You have reached $rankName',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            color: palette.onSurfaceVariant,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _RankHero extends StatelessWidget {
  final String rank;
  final _RankUpPalette palette;
  final AnimationController orbitController;
  final bool compact;
  final Color color;

  const _RankHero({
    required this.rank,
    required this.palette,
    required this.orbitController,
    required this.compact,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final heroSize = compact ? 220.0 : 280.0;
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
              width: heroSize * 1.1,
              height: heroSize * 1.1,
              repeat: true,
            ),
          ),
          Container(
            width: heroSize * 0.72,
            height: heroSize * 0.72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 40,
                  spreadRadius: 8,
                ),
              ],
            ),
          ),
          RankAssetIcon(
            rank: rank,
            size: heroSize * 0.8,
            decorated: false,
            iconScale: 1.1,
          ),
        ],
      ),
    );
  }
}

class _RankUpMessage extends StatelessWidget {
  final _RankUpPalette palette;
  final String oldRankName;
  final String newRankName;

  const _RankUpMessage({
    required this.palette,
    required this.oldRankName,
    required this.newRankName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: palette.primary.withValues(alpha: 0.2),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.auto_awesome_rounded, color: palette.primary, size: 32),
          const SizedBox(height: 12),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: palette.onSurfaceVariant,
                height: 1.4,
              ),
              children: [
                const TextSpan(text: 'Congratulations! You leaped from '),
                TextSpan(
                  text: oldRankName,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const TextSpan(text: ' to '),
                TextSpan(
                  text: newRankName,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: palette.primary,
                  ),
                ),
                const TextSpan(text: '. Keep up the great work!'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ContinueButton extends StatelessWidget {
  final _RankUpPalette palette;
  final VoidCallback onPressed;

  const _ContinueButton({required this.palette, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: palette.primary,
          foregroundColor: AppColors.surfaceLight,
          padding: const EdgeInsets.symmetric(vertical: 20),
          elevation: 4,
          shadowColor: palette.primary.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        onPressed: onPressed,
        child: const Text(
          'CONTINUE',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
          ),
        ),
      ),
    );
  }
}
