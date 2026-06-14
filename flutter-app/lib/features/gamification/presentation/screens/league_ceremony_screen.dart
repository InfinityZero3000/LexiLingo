import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/widgets/lottie_animation_widget.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

enum LeagueCeremonyType { promotion, demotion }

/// Full-screen ceremony shown when the user's league changes at week end.
///
/// Promoted: star-burst Lottie + league color gradient + upbeat copy.
/// Demoted: muted animation + neutral tone + motivational copy.
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
        transitionsBuilder: (_, anim, __, child) => FadeTransition(
          opacity: anim,
          child: child,
        ),
      ),
    );
  }

  @override
  State<LeagueCeremonyScreen> createState() => _LeagueCeremonyScreenState();
}

class _LeagueCeremonyScreenState extends State<LeagueCeremonyScreen>
    with TickerProviderStateMixin {
  late final AnimationController _badgeScale;
  late final AnimationController _textSlide;
  late final Animation<double> _scaleAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _badgeScale = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _textSlide = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _scaleAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _badgeScale, curve: Curves.elasticOut),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _textSlide, curve: Curves.easeOutCubic));

    Future.delayed(const Duration(milliseconds: 200), () {
      if (mounted) _badgeScale.forward();
    });
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) _textSlide.forward();
    });
  }

  @override
  void dispose() {
    _badgeScale.dispose();
    _textSlide.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visualData = rankVisualDataFor(widget.newLeague.toLowerCase());
    final leagueColor = isDark ? visualData.colorDark : visualData.color;
    final isPromotion = widget.type == LeagueCeremonyType.promotion;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Stack(
        alignment: Alignment.center,
        children: [
          // Gradient backdrop
          Container(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: Alignment.center,
                radius: 1.2,
                colors: [
                  leagueColor.withValues(alpha: isPromotion ? 0.3 : 0.12),
                  Colors.black.withValues(alpha: 0.85),
                ],
              ),
            ),
          ),

          // Lottie: star-burst for promotion, heartbeat for demotion
          if (isPromotion)
            const Positioned.fill(
              child: IgnorePointer(
                child: LottieAnimationWidget.starBurst(),
              ),
            ),

          // Content
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // Header
                  FadeTransition(
                    opacity: _textSlide,
                    child: Text(
                      isPromotion ? '🎉 Promoted!' : 'Keep Going!',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: leagueColor,
                        letterSpacing: 1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // League badge
                  ScaleTransition(
                    scale: _scaleAnim,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: leagueColor.withValues(alpha: 0.15),
                        border: Border.all(
                          color: leagueColor.withValues(alpha: 0.5),
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: leagueColor.withValues(alpha: 0.35),
                            blurRadius: 40,
                            spreadRadius: 8,
                          ),
                        ],
                      ),
                      child: Image.asset(
                        visualData.assetPath,
                        width: 72,
                        height: 72,
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) => Icon(
                          Icons.military_tech_rounded,
                          size: 64,
                          color: leagueColor,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 28),

                  // League name
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _textSlide,
                      child: Column(
                        children: [
                          Text(
                            _leagueName(widget.newLeague),
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            isPromotion
                                ? _promotionSubtitle(widget.previousLeague)
                                : _demotionSubtitle(widget.newLeague),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.white.withValues(alpha: 0.75),
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // CTA button
                  SlideTransition(
                    position: _slideAnim,
                    child: FadeTransition(
                      opacity: _textSlide,
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () {
                            Navigator.of(context).pop();
                            widget.onContinue();
                          },
                          style: FilledButton.styleFrom(
                            backgroundColor: leagueColor,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                          child: Text(
                            isPromotion ? 'Claim Your Spot!' : 'Fight Back!',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
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
