import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/games/presentation/theme/game_palette.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/xp_progress_bar.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/streak_indicator.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_card.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/daily_challenge_card.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/daily_challenge_mapper.dart';
import 'package:lexilingo_app/features/games/presentation/screens/game_screen_factory.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart'
    as progress;
import 'package:lexilingo_app/features/progress/presentation/providers/daily_challenges_provider.dart';

/// Main games hub screen — entry point for all English games.
///
/// Displays XP progress, streak, daily XP cap, level selector, game grid,
/// and a leaderboard preview.
class GamesHubScreen extends StatefulWidget {
  const GamesHubScreen({super.key});

  @override
  State<GamesHubScreen> createState() => _GamesHubScreenState();
}

class _GamesHubScreenState extends State<GamesHubScreen>
    with TickerProviderStateMixin {
  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  // Podium animation (skill: ui-ux-pro-max → staggered rise)
  late AnimationController _podiumController;
  late Animation<double> _anim2nd;
  late Animation<double> _anim1st;
  late Animation<double> _anim3rd;

  @override
  void initState() {
    super.initState();
    _podiumController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _anim2nd = CurvedAnimation(
      parent: _podiumController,
      curve: const Interval(0.0, 0.85, curve: Curves.easeOutBack),
    );
    _anim1st = CurvedAnimation(
      parent: _podiumController,
      curve: const Interval(0.15, 1.0, curve: Curves.easeOutBack),
    );
    _anim3rd = CurvedAnimation(
      parent: _podiumController,
      curve: const Interval(0.05, 0.90, curve: Curves.easeOutBack),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<GamesProvider>();
      p.loadXPProfile();
      p.loadLeaderboard();
      context.read<DailyChallengesProvider>().loadChallenges();
      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) _podiumController.forward();
      });
    });
  }

  @override
  void dispose() {
    _podiumController.dispose();
    super.dispose();
  }

  void _navigateToGame(BuildContext context, GameType gameType) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => gameScreenFor(gameType)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textInverted : AppColors.textDark;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Consumer2<GamesProvider, DailyChallengesProvider>(
        builder: (context, provider, challengesProvider, _) {
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1180),
              child: CustomScrollView(
                slivers: [
                  _buildAppBar(provider, titleColor),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: AppSpacing.lg),
                          _buildXpHeader(provider),
                          const SizedBox(height: AppSpacing.lg),
                          _buildDailyChallenge(context, challengesProvider),
                          const SizedBox(height: 20),
                          _buildLevelPicker(provider),
                          const SizedBox(height: 20),
                          _buildSectionTitle(
                            'gamesHub.gamesSectionTitle'.tr(),
                            titleColor,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildGameGrid(context, provider),
                          const SizedBox(height: AppSpacing.xl),
                          _buildSectionTitle(
                            'gamesHub.leaderboardSectionTitle'.tr(),
                            titleColor,
                          ),
                          const SizedBox(height: AppSpacing.md),
                          _buildLeaderboard(provider),
                          const SizedBox(height: AppSpacing.xxl),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  SliverAppBar _buildAppBar(GamesProvider provider, Color titleColor) {
    return SliverAppBar(
      floating: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      elevation: 0,
      title: Text(
        'gamesHub.title'.tr(),
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          color: titleColor,
          fontWeight: FontWeight.bold,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: AppSpacing.md),
          child: StreakIndicator(
            streakDays: provider.streakDays,
            compact: true,
          ),
        ),
      ],
    );
  }

  Widget _buildXpHeader(GamesProvider provider) {
    if (provider.isLoading && provider.xpProfile == null) {
      return Shimmer.fromColors(
        baseColor: AppColors.grey200,
        highlightColor: AppColors.grey100,
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
          ),
        ),
      );
    }

    if (provider.error != null && provider.xpProfile == null) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: Theme.of(context).colorScheme.error.withValues(alpha: 0.4),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                'gamesHub.xpLoadError'.tr(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              color: Theme.of(context).colorScheme.error,
              onPressed: () => provider.loadXPProfile(),
            ),
          ],
        ),
      );
    }

    final profile = provider.xpProfile;
    final dailyXp = provider.dailyXpToday;
    final dailyCap = dailyXp + provider.dailyCapRemaining;

    return Container(
      padding: EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          XPProgressBar(
            totalXp: profile?.totalXp ?? 0,
            numericLevel: profile?.numericLevel ?? 1,
            progressPercent: profile?.levelProgressPercent ?? 0,
            xpForNextLevel: profile?.xpForNextLevel ?? 100,
            currentXpInLevel: profile?.currentXpInLevel ?? 0,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: AppColors.textGrey,
                size: 16,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  'games.dailyXpToday'.tr(
                    namedArgs: {'current': '$dailyXp', 'cap': '$dailyCap'},
                  ),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColors.textGrey,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  progress.DailyChallengeEntity? _selectDailyChallenge(
    DailyChallengesProvider provider,
  ) {
    if (provider.challenges.isEmpty) return null;
    return provider.challenges.firstWhere(
      (challenge) => !challenge.isCompleted,
      orElse: () => provider.challenges.first,
    );
  }

  Future<void> _handleDailyChallengeTap(
    progress.DailyChallengeEntity challenge,
    DailyChallengesProvider provider,
  ) async {
    if (challenge.isCompleted) {
      final claimed = await provider.claimReward(challenge.id);
      if (!mounted) return;
      if (claimed) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('dailyChallenges.rewardClaimed'.tr())),
        );
        await provider.refresh();
      }
      return;
    }

    _navigateToGame(context, gameTypeForDailyChallenge(challenge));
  }

  Widget _buildDailyChallenge(
    BuildContext context,
    DailyChallengesProvider challengesProvider,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textInverted : AppColors.textDark;
    final selectedChallenge = _selectDailyChallenge(challengesProvider);
    final challenge = selectedChallenge != null
        ? toGameDailyChallenge(selectedChallenge)
        : DailyChallenge(
            gameType: GameType.fillBlank.apiKey,
            description: 'games.fillBlankChallenge'.tr(),
            bonusMultiplier: 2,
            completed: false,
            resetsAt: DateTime.now().add(const Duration(days: 1)),
          );
    final rewardClaimable =
        selectedChallenge?.isCompleted == true &&
        !challengesProvider.isRewardClaimed(selectedChallenge!.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('gamesHub.dailyChallengeLabel'.tr(), titleColor),
        const SizedBox(height: AppSpacing.sm),
        if (challengesProvider.isLoading && selectedChallenge == null)
          Shimmer.fromColors(
            baseColor: AppColors.grey200,
            highlightColor: AppColors.grey100,
            child: Container(
              height: 88,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
            ),
          )
        else
          DailyChallengeCard(
            challenge: challenge,
            allowCompletedTap: rewardClaimable,
            onTap: () {
              if (selectedChallenge != null) {
                _handleDailyChallengeTap(selectedChallenge, challengesProvider);
                return;
              }
              _navigateToGame(context, GameType.fillBlank);
            },
          ),
      ],
    );
  }

  Widget _buildLevelPicker(GamesProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark
        ? AppColors.textInverted.withValues(alpha: 0.7)
        : AppColors.textGrey;
    final unselectedLabel = isDark
        ? AppColors.textInverted
        : AppColors.textDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'gamesHub.difficultyLabel'.tr(),
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: titleColor,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _levels.map((level) {
              final selected = provider.selectedLevel == level;
              return Padding(
                padding: const EdgeInsets.only(right: AppSpacing.sm),
                child: ChoiceChip(
                  label: Text(level),
                  selected: selected,
                  onSelected: (_) => provider.setLevel(level),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? AppColors.textInverted : unselectedLabel,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    side: BorderSide(
                      color: selected ? AppColors.primary : AppColors.grey300,
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionTitle(String title, Color titleColor) {
    return Text(
      title,
      style: Theme.of(context).textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: titleColor,
      ),
    );
  }

  Widget _buildGameGrid(BuildContext context, GamesProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final crossAxisCount = adaptiveColumns(width);

        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          shrinkWrap: true,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.85,
          ),
          itemCount: GameType.values.length,
          itemBuilder: (context, index) {
            final type = GameType.values[index];
            return GameCard(
              gameType: type,
              onTap: () => _navigateToGame(context, type),
            );
          },
        );
      },
    );
  }

  Widget _buildLeaderboard(GamesProvider provider) {
    final board = provider.leaderboard;
    if (board.isEmpty) {
      return Container(
        padding: EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Center(
          child: Text(
            'gamesHub.noLeaderboardData'.tr(),
            style: TextStyle(color: AppColors.textGrey),
          ),
        ),
      );
    }

    final top3 = board.take(3).toList();
    final first = top3.isNotEmpty ? top3[0] : null;
    final second = top3.length > 1 ? top3[1] : null;
    final third = top3.length > 2 ? top3[2] : null;

    return Container(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.md,
        20,
        AppSpacing.md,
        AppSpacing.lg,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Podium: 2nd | 1st | 3rd (staggered rise animation)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (second != null)
                Expanded(
                  child: _buildPodiumColumn(second, 1, 72, AppColors.silver),
                ),
              if (second != null) const SizedBox(width: AppSpacing.sm),
              if (first != null)
                Expanded(
                  child: _buildPodiumColumn(first, 0, 104, AppColors.gold),
                ),
              if (third != null) const SizedBox(width: AppSpacing.sm),
              if (third != null)
                Expanded(
                  child: _buildPodiumColumn(third, 2, 56, AppColors.bronze),
                ),
            ],
          ),
          // 4th–8th entries below podium
          if (board.length > 3) ...[
            const SizedBox(height: AppSpacing.lg),
            const Divider(height: 1),
            ...board.skip(3).take(5).toList().asMap().entries.map((e) {
              final user = e.value;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final usernameColor = isDark
                  ? AppColors.textInverted
                  : AppColors.textDark;
              return ListTile(
                dense: true,
                leading: Container(
                  width: 28,
                  height: 28,
                  decoration: const BoxDecoration(
                    color: AppColors.grey200,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      '${e.key + 4}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  user.username,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: usernameColor,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${user.totalXp} XP',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                    Text(
                      'games.weeklyXp'.tr(
                        namedArgs: {'xp': '${user.weeklyXp}'},
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  /// Single podium column: avatar + name + XP + platform block.
  ///
  /// [rank] 0 = 1st (gold), 1 = 2nd (silver), 2 = 3rd (bronze).
  Widget _buildPodiumColumn(
    LeaderboardUser user,
    int rank,
    double podiumHeight,
    Color color,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final anims = [_anim1st, _anim2nd, _anim3rd];
    final anim = anims[rank];
    const rankLabels = ['1st', '2nd', '3rd'];
    const medalColors = [AppColors.gold, AppColors.silver, AppColors.bronze];
    final textColor = rank == 0
        ? GamePalette.goldOnLight
        : color.withValues(alpha: 0.85);
    final usernameColor = isDark ? AppColors.textInverted : AppColors.textDark;

    return AnimatedBuilder(
      animation: anim,
      builder: (context, child) => Opacity(
        opacity: anim.value.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, (1.0 - anim.value) * 60),
          child: child,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.workspace_premium_rounded,
            size: 24,
            color: medalColors[rank],
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: 0.15),
              border: Border.all(color: color, width: 2),
            ),
            child: Center(
              child: Text(
                user.username.isNotEmpty ? user.username[0].toUpperCase() : '?',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            user.username,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: usernameColor,
            ),
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
          const SizedBox(height: 2),
          Text(
            '${user.totalXp} XP',
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: AppColors.textGrey),
          ),
          const SizedBox(height: AppSpacing.sm),
          Container(
            width: double.infinity,
            height: podiumHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [color, color.withValues(alpha: 0.75)],
              ),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(8),
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              rankLabels[rank],
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.surfaceLight,
                shadows: [
                  Shadow(
                    color: Theme.of(
                      context,
                    ).shadowColor.withValues(alpha: 0.26),
                    offset: Offset(0, 1),
                    blurRadius: 2,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
