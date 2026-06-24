import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/social_stats_row.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart' as glass;
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

String formatMemberSince(BuildContext context, DateTime? createdAt) {
  if (createdAt == null) return 'profile.member'.tr();
  return 'profile.memberSince'.tr(
    namedArgs: {'date': DateFormat('MMM yyyy').format(createdAt)},
  );
}

IconData tierIcon(String tierCode) {
  switch (tierCode) {
    case 'A1':
      return Icons.eco;
    case 'A2':
      return Icons.spa;
    case 'B1':
      return Icons.bolt;
    case 'B2':
      return Icons.rocket_launch;
    case 'C1':
      return Icons.workspace_premium;
    case 'C2':
      return Icons.diamond;
    default:
      return Icons.star;
  }
}

Color tierColor(BuildContext context, String tierCode) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  switch (tierCode) {
    case 'A1':
      return AppColors.greenSuccessBright;
    case 'A2':
      return AppColors.teal;
    case 'B1':
      return AppColorRoles.primary(isDark);
    case 'B2':
      return AppColorRoles.primaryDeep(isDark);
    case 'C1':
      return AppColors.purple;
    case 'C2':
      return AppColors.warning;
    default:
      return AppColorRoles.primary(isDark);
  }
}

class ProfileHeader extends StatelessWidget {
  final dynamic user;
  final VoidCallback onProfileEdited;

  const ProfileHeader({
    super.key,
    required this.user,
    required this.onProfileEdited,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);
    return Consumer<LevelProvider>(
      builder: (context, levelProvider, child) {
        // Use numeric level progress, not CEFR-based
        final progress = levelProvider.displayLevelProgress;

        return Container(
          margin: const EdgeInsets.all(16),
          child: Stack(
            children: [
              // Glassmorphic Background Card
              ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          (isDark ? accent : AppColors.primary).withValues(
                            alpha: 0.15,
                          ),
                          (isDark ? accent : AppColors.primary).withValues(
                            alpha: 0.1,
                          ),
                          AppColors.surfaceLight.withValues(alpha: 0.05),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(
                        color: Theme.of(
                          context,
                        ).colorScheme.surface.withValues(alpha: 0.2),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: (isDark ? accent : AppColors.primary)
                              .withValues(alpha: 0.12),
                          blurRadius: 20,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        // Avatar with animated progress ring
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            // Progress Ring
                            glass.AnimatedProgressRing(
                              progress: progress,
                              size: 140,
                              strokeWidth: 6,
                              gradientColors: [
                                isDark ? accent : AppColors.primary,
                                isDark ? accent : AppColors.primary,
                                AppColors.purple,
                              ],
                              child: Container(
                                width: 120,
                                height: 120,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.surface
                                        .withValues(alpha: 0.5),
                                    width: 3,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isDark ? accent : AppColors.primary)
                                              .withValues(alpha: 0.3),
                                      blurRadius: 20,
                                      spreadRadius: 5,
                                    ),
                                  ],
                                ),
                                child: ClipOval(
                                  child: NetworkAvatarImage(
                                    imageUrl: user?.avatarUrl,
                                    fit: BoxFit.cover,
                                    width: 120,
                                    height: 120,
                                    fallback: Container(
                                      color:
                                          (isDark ? accent : AppColors.primary)
                                              .withValues(alpha: 0.2),
                                      child: Icon(
                                        Icons.person,
                                        size: 60,
                                        color: isDark
                                            ? accent
                                            : AppColors.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Verified Badge
                            if (user?.isVerified == true)
                              Positioned(
                                bottom: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: [
                                        isDark ? accent : AppColors.primary,
                                        isDark ? accent : AppColors.primary,
                                      ],
                                    ),
                                    shape: BoxShape.circle,
                                    border: Border.all(
                                      color: AppColors.surfaceLight,
                                      width: 2,
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color:
                                            (isDark
                                                    ? accent
                                                    : AppColors.primary)
                                                .withValues(alpha: 0.5),
                                        blurRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.verified,
                                    color: AppColors.surfaceLight,
                                    size: 16,
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 20),
                        // User Name
                        Text(
                          user?.displayName ?? 'profile.guestUser'.tr(),
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: -0.5,
                              ),
                        ),
                        const SizedBox(height: 6),
                        // Email
                        if (user?.email != null)
                          Text(
                            user.email,
                            style: const TextStyle(
                              color: AppColors.grey600,
                              fontSize: 13,
                            ),
                          ),
                        const SizedBox(height: 12),
                        // Level Badge + CEFR Proficiency Badge + Rank Badge
                        Consumer<LevelProvider>(
                          builder: (_, lp, __) {
                            final rankData = rankVisualDataFor(lp.rank);
                            final isMasterRank = lp.rank == 'master';
                            return Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              alignment: WrapAlignment.center,
                              children: [
                                // Numeric Level badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: AppColorRoles.primaryGradient(
                                        isDark,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(20),
                                    boxShadow: [
                                      BoxShadow(
                                        color: (isDark
                                                ? accent
                                                : AppColors.primary)
                                            .withValues(alpha: 0.4),
                                        blurRadius: 8,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.workspace_premium_rounded,
                                        color: AppColors.surfaceLight,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        'profile.level'.tr(
                                          namedArgs: {
                                            'level': '${lp.displayLevel}',
                                          },
                                        ),
                                        style: TextStyle(
                                          color: AppColors.surfaceLight,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // CEFR Proficiency Badge
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tierColor(
                                      context,
                                      lp.proficiencyLevel,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: tierColor(
                                        context,
                                        lp.proficiencyLevel,
                                      ).withValues(alpha: 0.5),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        tierIcon(lp.proficiencyLevel),
                                        size: 14,
                                        color: tierColor(
                                          context,
                                          lp.proficiencyLevel,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        lp.proficiencyLevel,
                                        style: TextStyle(
                                          color: tierColor(
                                            context,
                                            lp.proficiencyLevel,
                                          ),
                                          fontWeight: FontWeight.bold,
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        '·',
                                        style: TextStyle(
                                          color: tierColor(
                                            context,
                                            lp.proficiencyLevel,
                                          ).withValues(alpha: 0.6),
                                          fontSize: 13,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        lp.proficiencyName,
                                        style: TextStyle(
                                          color: tierColor(
                                            context,
                                            lp.proficiencyLevel,
                                          ),
                                          fontWeight: FontWeight.w500,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                // League Rank Badge
                                GestureDetector(
                                  onTap: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const LeaderboardScreen(),
                                    ),
                                  ),
                                  child: isMasterRank
                                      ? ShaderMask(
                                          shaderCallback: (bounds) =>
                                              const LinearGradient(
                                                colors: [
                                                  Color(0xFF5AB6FF),
                                                  Color(0xFFFFD64F),
                                                ],
                                                begin: Alignment.topLeft,
                                                end: Alignment.bottomRight,
                                              ).createShader(bounds),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 6,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white.withValues(
                                                alpha: 0.12,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(20),
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.4,
                                                ),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                RankAssetIcon(
                                                  rank: lp.rank,
                                                  size: 16,
                                                  decorated: false,
                                                ),
                                                const SizedBox(width: 5),
                                                Text(
                                                  lp.rankName,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        )
                                      : Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: rankData.color.withValues(
                                              alpha: 0.1,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(20),
                                            border: Border.all(
                                              color: rankData.color.withValues(
                                                alpha: 0.4,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              RankAssetIcon(
                                                rank: lp.rank,
                                                size: 16,
                                                decorated: false,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                lp.rankName,
                                                style: TextStyle(
                                                  color: rankData.color,
                                                  fontWeight: FontWeight.bold,
                                                  fontSize: 12,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        // Member Since
                        Text(
                          formatMemberSince(context, user?.createdAt),
                          style: const TextStyle(
                            color: AppColors.grey600,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 12),
                        // Edit Profile Button
                        GestureDetector(
                          onTap: () async {
                            final result = await Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => const EditProfileScreen(),
                              ),
                            );
                            if (result == true) {
                              onProfileEdited(); // Refresh after edit
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: AppColorRoles.primaryGradient(isDark),
                              ),
                              borderRadius: BorderRadius.circular(20),
                              boxShadow: [
                                BoxShadow(
                                  color: (isDark ? accent : AppColors.primary)
                                      .withValues(alpha: 0.3),
                                  blurRadius: 8,
                                  offset: Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.edit,
                                  color: AppColors.surfaceLight,
                                  size: 14,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'profile.editProfile'.tr(),
                                  style: TextStyle(
                                    color: AppColors.surfaceLight,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 20),
                        // Social Stats Row
                        const SocialStatsRow(),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
