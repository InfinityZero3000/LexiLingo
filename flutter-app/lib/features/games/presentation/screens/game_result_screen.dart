import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'dart:async';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/games/presentation/theme/game_palette.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/level_up_dialog.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/features/progress/presentation/widgets/streak_milestone_overlay.dart';
import 'package:provider/provider.dart';

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
  XPAwardResult? _xpResult;
  bool _isRetrying = false;

  int get _xpEarned => _xpResult?.xpAwarded ?? 0;

  @override
  void initState() {
    super.initState();
    _xpResult = widget.xpResult;

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
    final xpResult = _xpResult;
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

    // Sync streak state — backend already updated it via the game scoring route,
    // but Flutter's StreakProvider needs a refresh to reflect the new value in the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final streakProvider = context.read<StreakProvider>();
      await streakProvider.updateStreak();
      if (!mounted) return;
      if (streakProvider.milestoneJustReached) {
        await StreakMilestoneOverlay.show(
          context,
          streakDays: streakProvider.currentStreak,
          onDismiss: streakProvider.clearMilestone,
        );
      }
    });
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
    final xpResult = _xpResult;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(
          'games.resultTitle'.tr(
            namedArgs: {'game': result.gameType.displayName},
          ),
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: ContentWidth(
          maxWidth: ContentWidth.reading,
          child: Column(
            children: [
              const SizedBox(height: AppSpacing.sm),
              _buildStarRow(result.stars),
              const SizedBox(height: AppSpacing.xl),
              _buildScoreCard(result),
              const SizedBox(height: 20),
              _buildXpCard(xpResult),
              if (xpResult != null && xpResult.multiplier > 1.0) ...[
                const SizedBox(height: AppSpacing.md),
                _buildMultiplierBadge(xpResult.multiplier),
              ],
              const SizedBox(height: AppSpacing.xxl),
              _buildButtons(context),
            ],
          ),
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
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Icon(
              filled ? Icons.star_rounded : Icons.star_outline_rounded,
              color: filled
                  ? AppColors.accentYellow
                  : Theme.of(context).colorScheme.outline,
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
      padding: EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(result.gameType.icon, size: 32, color: AppColors.primary),
          const SizedBox(height: AppSpacing.sm),
          _statRow(
            'gameResult.accuracyLabel'.tr(),
            '${result.accuracy.toStringAsFixed(0)}%',
            color: result.accuracy >= 90
                ? AppColors.greenSuccess
                : result.accuracy >= 60
                ? AppColors.primary
                : AppColors.errorBright,
          ),
          _statRow(
            'gameResult.correctLabel'.tr(),
            '${result.correctAnswers}/${result.totalQuestions}',
          ),
          _statRow('gameResult.scoreLabel'.tr(), '${result.score}'),
          _statRow(
            'gameResult.durationLabel'.tr(),
            '${result.durationSeconds}s',
          ),
          _statRow('gameResult.levelLabel'.tr(), result.cefrLevel),
        ],
      ),
    );
  }

  Widget _statRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color ?? Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildXpCard(XPAwardResult? xpResult) {
    if (xpResult == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Column(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: Theme.of(context).colorScheme.onErrorContainer,
              size: 32,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'gameResult.xpNotAwarded'.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton.tonalIcon(
              onPressed: _isRetrying ? null : _retryAward,
              icon: _isRetrying
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
              label: Text('gameResult.retryXp'.tr()),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: GamePalette.skyGradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Text(
            'gameResult.xpEarnedLabel'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textInverted.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          AnimatedBuilder(
            animation: _xpAnimation,
            builder: (_, __) => Text(
              '+${_xpAnimation.value}',
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: AppColors.surfaceLight,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          _xpStatRow('gameResult.totalXpLabel'.tr(), '${xpResult.newTotalXp}'),
          _xpStatRow(
            'gameResult.dailyXpLabel'.tr(),
            '${xpResult.dailyXpToday}',
          ),
          _xpStatRow(
            'gameResult.streakLabel'.tr(),
            'profile.daysCount'.tr(
              namedArgs: {'count': '${xpResult.streakDays}'},
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _retryAward() async {
    setState(() => _isRetrying = true);
    final result = await context.read<GamesProvider>().retryLastCompletion();
    if (!mounted) return;
    setState(() {
      _isRetrying = false;
      _xpResult = result;
      _xpAnimation = IntTween(
        begin: 0,
        end: result?.xpAwarded ?? 0,
      ).animate(CurvedAnimation(parent: _xpController, curve: Curves.easeOut));
    });
    if (result != null) {
      _xpController
        ..reset()
        ..forward();
      if (result.leveledUp) {
        LevelUpDialog.show(
          context,
          newLevel: result.newLevel,
          xpAwarded: result.xpAwarded,
        );
      }
    }
  }

  Widget _xpStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.textInverted.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColors.surfaceLight,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiplierBadge(double multiplier) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: context.status.warningContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: context.status.warning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department_rounded,
            color: AppColors.orange,
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Flexible(
            child: Text(
              'gameResult.streakBonusLabel'.tr(
                namedArgs: {'multiplier': multiplier.toStringAsFixed(1)},
              ),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: context.status.warning,
                fontWeight: FontWeight.bold,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
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
          child: FilledButton(
            onPressed: () {
              Navigator.pop(context);
              if (widget.onPlayAgain != null) widget.onPlayAgain!();
            },
            style: FilledButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textInverted,
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              'gameResult.playAgainButton'.tr(),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
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
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              padding: const EdgeInsets.symmetric(vertical: 15),
              side: const BorderSide(color: AppColors.primary),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              'gameResult.backToGamesButton'.tr(),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
