import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

enum LeagueCeremonyType { promotion, demotion }

/// Full-screen ceremony shown when the user's league changes at week end.
///
/// Promoted: confetti burst + radar-pulse badge + league color gradient.
/// Demoted: muted gradient + neutral tone + motivational copy, no confetti.
class LeagueCeremonyScreen extends StatefulWidget {
  final String newLeague;
  final String? previousLeague;
  final LeagueCeremonyType type;
  final VoidCallback onContinue;

  const LeagueCeremonyScreen({
    super.key,
    required this.newLeague,
    this.previousLeague,
    required this.type,
    required this.onContinue,
  });

  static Future<void> show(
    BuildContext context, {
    required String newLeague,
    String? previousLeague,
    required LeagueCeremonyType type,
    required VoidCallback onContinue,
  }) {
    HapticFeedback.heavyImpact();
    return Navigator.of(context, rootNavigator: true).push(
      PageRouteBuilder(
        opaque: false,
        barrierColor: Colors.black.withValues(alpha: 0.85),
        transitionDuration: const Duration(milliseconds: 400),
        pageBuilder: (ctx, _, __) => LeagueCeremonyScreen(
          newLeague: newLeague,
          previousLeague: previousLeague,
          type: type,
          onContinue: onContinue,
        ),
        transitionsBuilder: (_, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  State<LeagueCeremonyScreen> createState() => _LeagueCeremonyScreenState();
}

class _LeagueCeremonyScreenState extends State<LeagueCeremonyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _sequence;
  late final AnimationController _ringPulse;
  late final Animation<double> _ringFade;
  late final Animation<double> _badgeScale;
  late final Animation<double> _headerFade;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _subtitleFade;
  late final Animation<double> _buttonFade;
  late final Animation<Offset> _buttonSlide;
  ConfettiController? _confetti;

  @override
  void initState() {
    super.initState();
    final isPromotion = widget.type == LeagueCeremonyType.promotion;

    _sequence = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );

    _ringFade = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
    );
    _badgeScale = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.05, 0.55, curve: Curves.easeOutBack),
    );
    _headerFade = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.0, 0.3, curve: Curves.easeOut),
    );
    final titleCurve = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.35, 0.75, curve: Curves.easeOutCubic),
    );
    _titleFade = titleCurve;
    _titleSlide = Tween<Offset>(
      begin: const Offset(0, 0.25),
      end: Offset.zero,
    ).animate(titleCurve);
    _subtitleFade = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
    );
    final buttonCurve = CurvedAnimation(
      parent: _sequence,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic),
    );
    _buttonFade = buttonCurve;
    _buttonSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(buttonCurve);

    _ringPulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );

    _sequence.forward();

    if (isPromotion) {
      _ringPulse.repeat();
      _confetti = ConfettiController(
        duration: const Duration(milliseconds: 1200),
      );
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) _confetti?.play();
      });
    }
  }

  @override
  void dispose() {
    _sequence.dispose();
    _ringPulse.dispose();
    _confetti?.dispose();
    super.dispose();
  }

  /// Picks a legible text color for a solid [background] fill,
  /// since pale league colors (silver, gold, platinum) wash out white text.
  Color _onColor(Color background) {
    return background.computeLuminance() > 0.5
        ? AppColors.textDark
        : AppColors.surfaceLight;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visualData = rankVisualDataFor(widget.newLeague.toLowerCase());
    final leagueColor = isDark ? visualData.colorDark : visualData.color;
    final isPromotion = widget.type == LeagueCeremonyType.promotion;
    final buttonTextColor = _onColor(leagueColor);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Layered gradient backdrop
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0, -0.2),
                radius: 1.3,
                colors: [
                  leagueColor.withValues(alpha: isPromotion ? 0.35 : 0.12),
                  const Color(0xFF0B0E14).withValues(alpha: 0.92),
                  const Color(0xFF05070A),
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
            ),
          ),

          // Contained confetti burst from the top — only for promotions.
          if (isPromotion && _confetti != null)
            Align(
              alignment: Alignment.topCenter,
              child: ConfettiWidget(
                confettiController: _confetti!,
                blastDirection: math.pi / 2,
                blastDirectionality: BlastDirectionality.explosive,
                maxBlastForce: 12,
                minBlastForce: 6,
                emissionFrequency: 0.06,
                numberOfParticles: 18,
                gravity: 0.25,
                shouldLoop: false,
                colors: [leagueColor, AppColors.surfaceLight, AppColors.gold],
              ),
            ),

          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FadeTransition(
                    opacity: _headerFade,
                    child: _StatusChip(
                      label: isPromotion ? 'PROMOTED' : 'DEMOTED',
                      color: leagueColor,
                      icon: isPromotion
                          ? Icons.arrow_upward_rounded
                          : Icons.arrow_downward_rounded,
                    ),
                  ),
                  const SizedBox(height: 32),

                  SizedBox(
                    width: 160,
                    height: 160,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        if (isPromotion)
                          AnimatedBuilder(
                            animation: _ringPulse,
                            builder: (context, _) {
                              final t = _ringPulse.value;
                              return Opacity(
                                opacity: (1 - t) * 0.6,
                                child: Transform.scale(
                                  scale: 1.0 + t * 0.45,
                                  child: Container(
                                    width: 132,
                                    height: 132,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: leagueColor,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        FadeTransition(
                          opacity: _ringFade,
                          child: ScaleTransition(
                            scale: _badgeScale,
                            child: Container(
                              width: 124,
                              height: 124,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    leagueColor.withValues(alpha: 0.28),
                                    leagueColor.withValues(alpha: 0.08),
                                  ],
                                ),
                                border: Border.all(
                                  color: leagueColor.withValues(alpha: 0.7),
                                  width: 3,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: leagueColor.withValues(alpha: 0.4),
                                    blurRadius: 36,
                                    spreadRadius: 4,
                                  ),
                                ],
                              ),
                              child: Image.asset(
                                visualData.assetPath,
                                width: 76,
                                height: 76,
                                fit: BoxFit.contain,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.military_tech_rounded,
                                  size: 64,
                                  color: leagueColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  SlideTransition(
                    position: _titleSlide,
                    child: FadeTransition(
                      opacity: _titleFade,
                      child: Text(
                        _leagueName(widget.newLeague),
                        style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.w900,
                          color: AppColors.surfaceLight,
                          letterSpacing: -0.5,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  FadeTransition(
                    opacity: _subtitleFade,
                    child: Text(
                      isPromotion
                          ? _promotionSubtitle(widget.previousLeague)
                          : _demotionSubtitle(widget.newLeague),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColors.surfaceLight.withValues(alpha: 0.72),
                        height: 1.5,
                      ),
                    ),
                  ),
                  const SizedBox(height: 44),

                  SlideTransition(
                    position: _buttonSlide,
                    child: FadeTransition(
                      opacity: _buttonFade,
                      child: SizedBox(
                        width: double.infinity,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                leagueColor,
                                Color.lerp(
                                  leagueColor,
                                  Colors.black,
                                  0.25,
                                )!, // darken, not a token
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: leagueColor.withValues(alpha: 0.45),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Material(
                            color: Colors.transparent,
                            borderRadius: BorderRadius.circular(16),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () {
                                Navigator.of(context).pop();
                                widget.onContinue();
                              },
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                                child: Center(
                                  child: Text(
                                    isPromotion
                                        ? 'Claim Your Spot!'
                                        : 'Fight Back!',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 16,
                                      color: buttonTextColor,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _leagueName(String league) =>
      league[0].toUpperCase() + league.substring(1);

  String _promotionSubtitle(String? previous) {
    final from = previous != null ? 'from ${_leagueName(previous)} ' : '';
    return 'You\'ve been promoted ${from}to ${_leagueName(widget.newLeague)} League!\nKeep the momentum going this week.';
  }

  String _demotionSubtitle(String current) =>
      'You dropped to ${_leagueName(current)} League.\nBut every champion starts from the bottom — come back stronger!';
}

class _StatusChip extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;

  const _StatusChip({
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}
