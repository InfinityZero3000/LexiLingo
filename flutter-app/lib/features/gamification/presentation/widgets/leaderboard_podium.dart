import 'dart:ui';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/leaderboard_entry.dart';
import 'package:lexilingo_app/features/gamification/presentation/widgets/rank_asset_icon.dart';

/// Leaderboard Podium Widget
/// Displays the top 3 users on a podium
class LeaderboardPodium extends StatefulWidget {
  final String league;
  final List<LeaderboardEntryEntity> topThree;
  final List<LeaderboardEntryEntity> entries;
  final int totalParticipants;
  final Future<void> Function()? onRefresh;
  final void Function(LeaderboardEntryEntity?)? onEntrySelected;

  const LeaderboardPodium({
    super.key,
    required this.league,
    required this.topThree,
    required this.entries,
    required this.totalParticipants,
    this.onRefresh,
    this.onEntrySelected,
  });

  @override
  State<LeaderboardPodium> createState() => _LeaderboardPodiumState();
}

class _LeaderboardPodiumState extends State<LeaderboardPodium> {
  LeaderboardEntryEntity? _selectedEntry;

  @override
  void initState() {
    super.initState();
    _selectedEntry = _findCurrentUserEntry(widget.entries);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onEntrySelected?.call(_selectedEntry);
    });
  }

  @override
  void didUpdateWidget(LeaderboardPodium oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entries != widget.entries) {
      final previous = _selectedEntry;
      if (previous != null) {
        // Keep tracking the same user if they're still in the new list
        final updated = widget.entries.where((e) => e.userId == previous.userId);
        _selectedEntry = updated.isNotEmpty
            ? updated.first
            : _findCurrentUserEntry(widget.entries);
      } else {
        _selectedEntry = _findCurrentUserEntry(widget.entries);
      }
    }
  }

  LeaderboardEntryEntity? _findCurrentUserEntry(List<LeaderboardEntryEntity> entries) {
    final currentUserEntries = entries.where((e) => e.isCurrentUser);
    if (currentUserEntries.isNotEmpty) return currentUserEntries.first;
    return entries.isNotEmpty ? entries.first : null;
  }

  void _onEntryTap(LeaderboardEntryEntity entry) {
    setState(() {
      _selectedEntry = entry;
    });
    widget.onEntrySelected?.call(entry);
  }

  static const _backgroundAspectRatio = 941 / 1672;

  @override
  Widget build(BuildContext context) {
    final first = widget.topThree.isNotEmpty ? widget.topThree[0] : null;
    final second = widget.topThree.length > 1 ? widget.topThree[1] : null;
    final third = widget.topThree.length > 2 ? widget.topThree[2] : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final backgroundHeight = width / _backgroundAspectRatio;

        return SizedBox(
          width: width,
          height: constraints.maxHeight,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              // Dont change slot positions, they are carefully calculated to fit the background design
              _buildHonorSlot(
                context,
                canvasWidth: width,
                backgroundHeight: backgroundHeight,
                entry: first,
                rank: 1,
                centerX: 0.5,
                centerY: 0.17,
              ),
              _buildHonorSlot(
                context,
                canvasWidth: width,
                backgroundHeight: backgroundHeight,
                entry: second,
                rank: 2,
                centerX: 0.265,
                centerY: 0.368,
              ),
              _buildHonorSlot(
                context,
                canvasWidth: width,
                backgroundHeight: backgroundHeight,
                entry: third,
                rank: 3,
                centerX: 0.735,
                centerY: 0.368,
              ),
              DraggableScrollableSheet(
                initialChildSize: 0.38,
                minChildSize: 0.38,
                maxChildSize: 0.67,
                snap: true,
                snapSizes: const [0.38, 0.67],
                builder: (context, scrollController) {
                  return _buildRankingListPanel(context, scrollController);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHonorSlot(
    BuildContext context, {
    required LeaderboardEntryEntity? entry,
    required int rank,
    required double canvasWidth,
    required double backgroundHeight,
    required double centerX,
    required double centerY,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final avatarSize = (canvasWidth * (rank == 1 ? 0.255 : 0.185))
        .clamp(rank == 1 ? 86.0 : 64.0, rank == 1 ? 150.0 : 98.0)
        .toDouble();
    final labelWidth = (avatarSize * (rank == 1 ? 1.58 : 1.76))
        .clamp(112.0, rank == 1 ? 166.0 : 150.0)
        .toDouble();
    final left = canvasWidth * centerX - labelWidth / 2;
    final top = backgroundHeight * centerY - avatarSize / 2;
    final rankColor = _getRankColor(rank);

    return Positioned(
      left: left,
      top: top,
      width: labelWidth,
      child: GestureDetector(
        onTap: entry != null ? () => _onEntryTap(entry) : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              alignment: Alignment.center,
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: avatarSize,
                  height: avatarSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0.98),
                        rankColor.withValues(alpha: 0.2),
                      ],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(
                      color: entry?.isCurrentUser == true
                          ? primaryColor
                          : Colors.white.withValues(alpha: 0.96),
                      width: rank == 1 ? 4 : 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: rankColor.withValues(alpha: 0.35),
                        blurRadius: rank == 1 ? 18 : 14,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: ClipOval(
                    child: entry != null
                        ? NetworkAvatarImage(
                            imageUrl: entry.avatarUrl,
                            fallback: _buildInitialAvatar(context, entry),
                          )
                        : Icon(
                            Icons.person_outline,
                            color: Colors.grey[400],
                            size: avatarSize * 0.46,
                          ),
                  ),
                ),
                Positioned(
                  bottom: -6,
                  child: Container(
                    width: avatarSize * 0.36,
                    height: avatarSize * 0.36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: rankColor,
                      border: Border.all(color: Colors.white, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.16),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Text(
                      '$rank',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: avatarSize * 0.17,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 13),
            if (entry != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.74),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.72),
                    width: 1,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.08),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      entry.displayName,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: rank == 1 ? 13 : 12,
                        fontWeight: entry.isCurrentUser
                            ? FontWeight.w800
                            : FontWeight.w700,
                        color: entry.isCurrentUser
                            ? primaryColor
                            : AppColors.textDark,
                      ),
                    ),
                  ],
                ),
              )
            else
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.68),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '---',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColorRoles.textMuted(isDark),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitialAvatar(
    BuildContext context,
    LeaderboardEntryEntity entry,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallback = entry.displayName.isNotEmpty
        ? entry.displayName[0]
        : (entry.username.isNotEmpty ? entry.username[0] : '?');

    return Container(
      color: entry.isCurrentUser
          ? AppColorRoles.primary(isDark).withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.82),
      child: Center(
        child: Text(
          fallback.toUpperCase(),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: entry.isCurrentUser
                ? AppColorRoles.primary(isDark)
                : Colors.grey[600],
          ),
        ),
      ),
    );
  }

  Widget _buildRankingListPanel(
    BuildContext context,
    ScrollController scrollController,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = Colors.white.withValues(alpha: isDark ? 0.14 : 0.68);
    final panelColor = isDark
        ? AppColors.surfaceDark.withValues(alpha: 0.82)
        : Colors.white.withValues(alpha: 0.85);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              color: panelColor,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(24),
              ),
              border: Border(
                top: BorderSide(color: borderColor, width: 1.2),
                left: BorderSide(color: borderColor, width: 1.2),
                right: BorderSide(color: borderColor, width: 1.2),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: RefreshIndicator(
              onRefresh: widget.onRefresh ?? () async {},
              child: CustomScrollView(
                controller: scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Drag Handle & League Info
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
                      child: Column(
                        children: [
                          Container(
                            width: 40,
                            height: 4,
                            margin: const EdgeInsets.only(bottom: 12),
                            decoration: BoxDecoration(
                              color: Colors.grey.withValues(alpha: 0.5),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          _buildLeaguePanelHeader(context),
                        ],
                      ),
                    ),
                  ),
                  // Ranking list items
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    sliver: widget.entries.isEmpty
                        ? SliverToBoxAdapter(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 18),
                              child: Text(
                                'leaderboard.noRankingsYet'.tr(),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isDark
                                      ? AppColorRoles.textSecondary(isDark)
                                      : AppColors.textMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              return _buildGlassRankingRow(
                                context,
                                entry: widget.entries[index],
                              );
                            }, childCount: widget.entries.length),
                          ),
                  ),
                  // Bottom spacing
                  const SliverToBoxAdapter(child: SizedBox(height: 24)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLeaguePanelHeader(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        RankAssetIcon(rank: widget.league, size: 34),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'leaderboard.title'.tr(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: isDark ? AppColors.textInverted : AppColors.textDark,
                ),
              ),
              widget.league == 'master'
                  ? ShaderMask(
                      shaderCallback: (bounds) => const LinearGradient(
                        colors: [Color(0xFF5AB6FF), Color(0xFFFFD64F)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ).createShader(bounds),
                      child: Text(
                        rankDisplayNameFor(widget.league),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                        ),
                      ),
                    )
                  : Text(
                      rankDisplayNameFor(widget.league),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: rankVisualDataFor(widget.league).color,
                      ),
                    ),
            ],
          ),
        ),
        Text(
          'leaderboard.participants'.tr(
            namedArgs: {'count': widget.totalParticipants.toString()},
          ),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: AppColorRoles.textMuted(isDark),
          ),
        ),
      ],
    );
  }

  Widget _buildGlassRankingRow(
    BuildContext context, {
    required LeaderboardEntryEntity entry,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);
    final rankColor = _getRankColor(entry.rank);
    final name = entry.displayName.isNotEmpty
        ? entry.displayName
        : entry.username;
    final isSelected = _selectedEntry?.userId == entry.userId;

    return GestureDetector(
      onTap: () => _onEntryTap(entry),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.symmetric(vertical: 5),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? primaryColor.withValues(alpha: isDark ? 0.28 : 0.16)
              : entry.isCurrentUser
              ? primaryColor.withValues(alpha: isDark ? 0.22 : 0.13)
              : Colors.white.withValues(alpha: isDark ? 0.08 : 0.48),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? primaryColor.withValues(alpha: 0.7)
                : entry.isCurrentUser
                ? primaryColor.withValues(alpha: 0.52)
                : Colors.white.withValues(alpha: isDark ? 0.1 : 0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: rankColor.withValues(alpha: 0.15),
                border: Border.all(color: rankColor.withValues(alpha: 0.5)),
              ),
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: rankColor,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.72),
                border: Border.all(
                  color: entry.isCurrentUser
                      ? primaryColor
                      : Colors.white.withValues(alpha: 0.84),
                  width: entry.isCurrentUser ? 2 : 1,
                ),
              ),
              child: ClipOval(
                child: NetworkAvatarImage(
                  imageUrl: entry.avatarUrl,
                  fallback: _buildInitialAvatar(context, entry),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: entry.isCurrentUser
                                ? FontWeight.w800
                                : FontWeight.w700,
                            color: entry.isCurrentUser
                                ? primaryColor
                                : (isDark
                                      ? AppColors.textInverted
                                      : AppColors.textDark),
                          ),
                        ),
                      ),
                      if (entry.isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      RankAssetIcon(
                        rank: entry.userRank,
                        size: 18,
                        decorated: false,
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          '${rankDisplayNameFor(entry.userRank)} · ${entry.lessonsCompleted} lessons',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColorRoles.textMuted(isDark),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              constraints: const BoxConstraints(minWidth: 64),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.gold.withValues(alpha: isDark ? 0.22 : 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: AppColors.gold.withValues(alpha: 0.3)),
              ),
              child: Text(
                '${entry.xpEarned} XP',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: AppColors.goldDark,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.gold;
      case 2:
        return AppColors.textMuted;
      case 3:
        return AppColors.bronze;
      default:
        return Colors.grey;
    }
  }
}

/// Leaderboard Entry Row Widget
class LeaderboardEntryRow extends StatelessWidget {
  final LeaderboardEntryEntity entry;
  final VoidCallback? onTap;

  const LeaderboardEntryRow({super.key, required this.entry, this.onTap});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = AppColorRoles.primary(isDark);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: entry.isCurrentUser
              ? primaryColor.withValues(alpha: 0.08)
              : (isDark ? AppColors.surfaceDark : AppColors.surfaceLight),
          border: Border.all(
            color: entry.isCurrentUser
                ? primaryColor.withValues(alpha: 0.5)
                : Colors.grey.withValues(alpha: 0.12),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: _getRankColor(entry.rank).withValues(alpha: 0.45),
                ),
              ),
              child: Text(
                '${entry.rank}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _getRankColor(entry.rank),
                ),
              ),
            ),

            const SizedBox(width: 10),

            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: entry.isCurrentUser
                    ? primaryColor.withValues(alpha: 0.2)
                    : Colors.grey[200],
                border: entry.isCurrentUser
                    ? Border.all(color: primaryColor, width: 2)
                    : null,
              ),
              child: ClipOval(
                child: NetworkAvatarImage(
                  imageUrl: entry.avatarUrl,
                  fallback: _buildInitial(context),
                ),
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.displayName,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: entry.isCurrentUser
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: entry.isCurrentUser
                                ? primaryColor
                                : (isDark
                                      ? AppColors.textInverted
                                      : AppColors.textDark),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isCurrentUser) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryColor,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'YOU',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: AppColors.surfaceLight,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(
                    '${entry.lessonsCompleted} lessons completed',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),

            Container(
              constraints: const BoxConstraints(minWidth: 68),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${entry.xpEarned}',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.deepOrange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInitial(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fallback = entry.displayName.isNotEmpty
        ? entry.displayName[0]
        : (entry.username.isNotEmpty ? entry.username[0] : '?');

    return Center(
      child: Text(
        fallback.toUpperCase(),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.bold,
          color: entry.isCurrentUser
              ? AppColorRoles.primary(isDark)
              : Colors.grey[600],
        ),
      ),
    );
  }

  Color _getRankColor(int rank) {
    switch (rank) {
      case 1:
        return AppColors.orange;
      case 2:
        return AppColors.textMuted;
      case 3:
        return AppColors.warning;
      default:
        return Colors.grey;
    }
  }
}
