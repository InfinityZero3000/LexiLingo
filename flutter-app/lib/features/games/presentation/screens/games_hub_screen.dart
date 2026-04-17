import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/games/domain/entities/game_entities.dart';
import 'package:lexilingo_app/features/games/presentation/providers/games_provider.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/xp_progress_bar.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/streak_indicator.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/game_card.dart';
import 'package:lexilingo_app/features/games/presentation/widgets/daily_challenge_card.dart';
import 'package:lexilingo_app/features/games/presentation/screens/word_scramble_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/fill_blank_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/matching_game_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/spelling_bee_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/grammar_quiz_screen.dart';
import 'package:lexilingo_app/features/games/presentation/screens/hangman_screen.dart';

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
    Widget screen;
    switch (gameType) {
      case GameType.wordScramble:
        screen = const WordScrambleScreen();
      case GameType.fillBlank:
        screen = const FillBlankScreen();
      case GameType.matching:
        screen = const MatchingGameScreen();
      case GameType.spellingBee:
        screen = const SpellingBeeScreen();
      case GameType.grammarQuiz:
        screen = const GrammarQuizScreen();
      case GameType.hangman:
        screen = const HangmanScreen();
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textInverted : AppColors.textDark;
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surfaceContainer,
      body: Consumer<GamesProvider>(
        builder: (context, provider, _) {
          return CustomScrollView(
            slivers: [
              _buildAppBar(provider, titleColor),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildXpHeader(provider),
                      const SizedBox(height: 16),
                      _buildDailyChallenge(context),
                      const SizedBox(height: 20),
                      _buildLevelPicker(provider),
                      const SizedBox(height: 20),
                      _buildSectionTitle('Games', titleColor),
                      const SizedBox(height: 12),
                      _buildGameGrid(context, provider),
                      const SizedBox(height: 24),
                      _buildSectionTitle('Leaderboard', titleColor),
                      const SizedBox(height: 12),
                      _buildLeaderboard(provider),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ],
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
        'Games',
        style: TextStyle(
          color: titleColor,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 12),
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
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      );
    }

    if (provider.error != null && provider.xpProfile == null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline_rounded, color: Colors.red.shade400),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Failed to load XP profile. Tap to retry.',
                style: TextStyle(color: Colors.red.shade700, fontSize: 13),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              color: Colors.red.shade400,
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
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
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
        children: [
          XPProgressBar(
            totalXp: profile?.totalXp ?? 0,
            numericLevel: profile?.numericLevel ?? 1,
            progressPercent: profile?.levelProgressPercent ?? 0,
            xpForNextLevel: profile?.xpForNextLevel ?? 100,
            currentXpInLevel: profile?.currentXpInLevel ?? 0,
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.bolt_rounded,
                color: AppColors.textGrey,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '$dailyXp/$dailyCap XP today',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textGrey,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Hardcoded demo daily challenge card.
  ///
  /// In production this would be loaded from the backend.
  Widget _buildDailyChallenge(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? AppColors.textInverted : AppColors.textDark;
    final demo = DailyChallenge(
      gameType: GameType.fillBlank.apiKey,
      description: 'Complete 5 Fill in the Blank questions',
      bonusMultiplier: 2,
      completed: false,
      resetsAt: DateTime.now().add(const Duration(days: 1)),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Daily Challenge', titleColor),
        const SizedBox(height: 10),
        DailyChallengeCard(
          challenge: demo,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const FillBlankScreen()),
          ),
        ),
      ],
    );
  }

  Widget _buildLevelPicker(GamesProvider provider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white70 : AppColors.textGrey;
    final unselectedLabel = isDark
        ? AppColors.textInverted
        : AppColors.textDark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Difficulty',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: titleColor,
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _levels.map((level) {
              final selected = provider.selectedLevel == level;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(level),
                  selected: selected,
                  onSelected: (_) => provider.setLevel(level),
                  selectedColor: AppColors.primary,
                  labelStyle: TextStyle(
                    color: selected ? Colors.white : unselectedLabel,
                    fontWeight: FontWeight.bold,
                  ),
                  backgroundColor: Theme.of(context).colorScheme.surface,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
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
      style: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.bold,
        color: titleColor,
      ),
    );
  }

  Widget _buildGameGrid(BuildContext context, GamesProvider provider) {
    return GridView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
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
  }

  Widget _buildLeaderboard(GamesProvider provider) {
    final board = provider.leaderboard;
    if (board.isEmpty) {
      return Container(
        padding: EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: Text(
            'No leaderboard data yet.',
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
      padding: EdgeInsets.fromLTRB(12, 20, 12, 16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
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
              if (second != null) const SizedBox(width: 8),
              if (first != null)
                Expanded(
                  child: _buildPodiumColumn(first, 0, 104, AppColors.gold),
                ),
              if (third != null) const SizedBox(width: 8),
              if (third != null)
                Expanded(
                  child: _buildPodiumColumn(third, 2, 56, AppColors.bronze),
                ),
            ],
          ),
          // 4th–8th entries below podium
          if (board.length > 3) ...[
            const SizedBox(height: 16),
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
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textGrey,
                      ),
                    ),
                  ),
                ),
                title: Text(
                  user.username,
                  style: TextStyle(
                    color: usernameColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${user.totalXp} XP',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      '${user.weeklyXp} this week',
                      style: const TextStyle(
                        fontSize: 11,
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
        ? const Color(0xFF9A7A00) // dark gold for legibility
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
          const SizedBox(height: 4),
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
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            user.username,
            style: TextStyle(
              fontSize: 11,
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
            style: const TextStyle(fontSize: 10, color: AppColors.textGrey),
          ),
          const SizedBox(height: 6),
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
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppColors.surfaceLight,
                fontSize: 15,
                shadows: [
                  Shadow(
                    color: Colors.black26,
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
