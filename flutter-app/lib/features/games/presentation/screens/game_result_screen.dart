import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/level_up_dialog.dart';

/// Shows the result after completing any game session.
///
/// Displays star rating, animated XP count-up, streak multiplier,
/// and triggers level-up dialog if the player levelled up.
class GameResultScreen extends StatefulWidget {
  final GameResult result;
  final XPAwardResult? xpResult;
  final VoidCallback? onPlayAgain;

  const GameResultScreen({
    super.key,
    required this.result,
    this.xpResult,
    this.onPlayAgain,
  });

  @override
  State<GameResultScreen> createState() => _GameResultScreenState();
}

class _GameResultScreenState extends State<GameResultScreen>
    with TickerProviderStateMixin {
  late AnimationController _xpController;
  late Animation<int> _xpAnimation;
  late AnimationController _starsController;
  late Animation<double> _starsAnimation;

  int get _xpEarned => widget.xpResult?.xpAwarded ?? widget.result.xpEarned;

  @override
  void initState() {
    super.initState();

    _xpController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
    _xpAnimation = IntTween(
      begin: 0,
      end: _xpEarned,
    ).animate(CurvedAnimation(parent: _xpController, curve: Curves.easeOut));

    _starsController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _starsAnimation = CurvedAnimation(
      parent: _starsController,
      curve: Curves.elasticOut,
    );

    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _starsController.forward();
        _xpController.forward();
      }
    });

    // Show level-up dialog after brief delay
    final xpResult = widget.xpResult;
    if (xpResult != null && xpResult.leveledUp) {
      Future.delayed(const Duration(milliseconds: 1800), () {
        if (mounted) {
          LevelUpDialog.show(
            context,
            newLevel: xpResult.newLevel,
            xpAwarded: xpResult.xpAwarded,
          );
        }
      });
    }
  }

  @override
  void dispose() {
    _xpController.dispose();
    _starsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final xpResult = widget.xpResult;

    return Scaffold(
      backgroundColor: AppColors.backgroundLight,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          '${result.gameType.displayName} — Result',
          style: const TextStyle(color: AppColors.textDark),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildStarRow(result.stars),
            const SizedBox(height: 24),
            _buildScoreCard(result),
            const SizedBox(height: 20),
            _buildXpCard(xpResult),
            if (xpResult != null && xpResult.multiplier > 1.0) ...[
              const SizedBox(height: 12),
              _buildMultiplierBadge(xpResult.multiplier),
            ],
            const SizedBox(height: 32),
            _buildButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStarRow(int stars) {
    return ScaleTransition(
      scale: _starsAnimation,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(3, (i) {
          final filled = i < stars;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: filled ? AppColors.accentYellow : AppColors.grey300,
              size: filled ? 52 : 44,
            ),
          );
        }),
      ),
    );
  }

  Widget _buildScoreCard(GameResult result) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.gameType.icon, size: 32, color: AppColors.primary),
          const SizedBox(height: 8),
          _statRow(
            'Accuracy',
            '${result.accuracy.toStringAsFixed(0)}%',
            color: result.accuracy >= 90
                ? AppColors.greenSuccess
                : result.accuracy >= 60
                ? AppColors.primary
                : Colors.red,
          ),
          _statRow(
            'Correct',
            '${result.correctAnswers}/${result.totalQuestions}',
          ),
          _statRow('Score', '${result.score}'),
          _statRow('Duration', '${result.durationSeconds}s'),
          _statRow('Level', result.cefrLevel),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textGrey, fontSize: 14),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: color ?? AppColors.textDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXpCard(XPAwardResult? xpResult) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF38B2FF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          const Text(
            'XP Earned',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 6),
          AnimatedBuilder(
            animation: _xpAnimation,
            builder: (_, __) => Text(
              '+${_xpAnimation.value}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 40,
              ),
            ),
          ),
          if (xpResult != null) ...[
            const SizedBox(height: 8),
            _xpStatRow('Total XP', '${xpResult.newTotalXp}'),
            _xpStatRow('Daily XP', '${xpResult.dailyXpToday}'),
            _xpStatRow('Streak', '${xpResult.streakDays} days'),
          ],
        ],
      ),
    );
  }

  Widget _xpStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiplierBadge(double multiplier) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade300),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: Colors.orange,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            'Streak bonus: ${multiplier.toStringAsFixed(1)}x',
            style: TextStyle(
              color: Colors.orange.shade800,
              fontWeight: FontWeight.bold,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildButtons(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.onPlayAgain != null) widget.onPlayAgain!();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Play Again',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              // Pop back to hub
              Navigator.popUntil(
                context,
                (route) => route.isFirst || route.settings.name == '/games',
              );
            },
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Back to Games',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
