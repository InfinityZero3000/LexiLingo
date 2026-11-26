import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/features/gamification/gamification.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/profile/presentation/pages/edit_profile_screen.dart';
import 'package:lexilingo_app/features/profile/presentation/widgets/profile_page/social_stats_row.dart';
import 'package:lexilingo_app/core/widgets/glassmorphic_components.dart'
    as glass;
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

String formatMemberSinceDate(DateTime createdAt, String locale) =>
    DateFormat('MMM yyyy', locale).format(createdAt);

String formatMemberSince(BuildContext context, DateTime? createdAt) {
  if (createdAt == null) return 'profile.member'.tr();
  return 'profile.memberSince'.tr(
    namedArgs: {
      'date': formatMemberSinceDate(
        createdAt,
        Localizations.localeOf(context).languageCode,
      ),
    },
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
      return context.status.success;
    case 'A2':
      return AppColors.teal;
    case 'B1':
      return AppColorRoles.primary(isDark);
    case 'B2':
      return AppColorRoles.primaryDeep(isDark);
    case 'C1':
      return AppColors.purple;
    case 'C2':
      return context.status.warning;
    default:
      return AppColorRoles.primary(isDark);
  }
}

class ProfileHeader extends StatelessWidget {
  final UserEntity? user;
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
          margin: const EdgeInsets.all(AppSpacing.lg),
          child: Stack(
            children: [
              // Glassmorphic Background Card
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        (isDark
                                ? accent
                                : Theme.of(context).colorScheme.primary)
                            .withValues(alpha: 0.15),
                        (isDark
                                ? accent
                                : Theme.of(context).colorScheme.primary)
                            .withValues(alpha: 0.1),
                        AppColors.surfaceLight.withValues(alpha: 0.05),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(AppRadius.xl),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.surface.withValues(alpha: 0.2),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:
                            (isDark
                                    ? accent
                                    : Theme.of(context).colorScheme.primary)
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
                            size: 104,
                            strokeWidth: 5,
                            gradientColors: [
                              isDark
                                  ? accent
                                  : Theme.of(context).colorScheme.primary,

                              isDark
                                  ? accent
                                  : Theme.of(context).colorScheme.primary,

                              AppColors.purple,
                            ],
                            child: Container(
                              width: 88,
                              height: 88,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.surface.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        (isDark
                                                ? accent
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.primary)
                                            .withValues(alpha: 0.3),
                                    blurRadius: 16,
                                    spreadRadius: 3,
                                  ),
                                ],
                              ),
                              child: ClipOval(
                                child: NetworkAvatarImage(
                                  imageUrl: user?.avatarUrl,
                                  fit: BoxFit.cover,
                                  width: 88,
                                  height: 88,
                                  fallback: Container(
                                    color:
                                        (isDark
                                                ? accent
                                                : Theme.of(
                                                    context,
                                                  ).colorScheme.primary)
                                            .withValues(alpha: 0.2),
                                    child: Icon(
                                      Icons.person,
                                      size: 40,
                                      color: isDark
                                          ? accent
                                          : Theme.of(
                                              context,
                                            ).colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          // Verified Badge
                          if (user?.isVerified == true)
                            Positioned(
                              bottom: 4,
                              right: 4,
                              child: Semantics(
                                label: 'profile.emailVerified'.tr(),
                                child: Tooltip(
                                  message: 'profile.emailVerified'.tr(),
                                  excludeFromSemantics: true,
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          isDark
                                              ? accent
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,

                                          isDark
                                              ? accent
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
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
                                                      : Theme.of(
                                                          context,
                                                        ).colorScheme.primary)
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
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.md),
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
                      if (user != null)
                        Text(
                          user!.email,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: AppColorRoles.textSecondary(isDark),
                              ),
                        ),
                      const SizedBox(height: AppSpacing.md),
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
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: AppColorRoles.primaryGradient(
                                      isDark,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.lg,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color:
                                          (isDark
                                                  ? accent
                                                  : Theme.of(
                                                      context,
                                                    ).colorScheme.primary)
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
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: AppColors.surfaceLight,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              // CEFR Proficiency Badge. The level name
                              // moved to a tooltip so the three badges fit
                              // one row at 375px.
                              Tooltip(
                                message: lp.proficiencyName,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: AppSpacing.md,
                                    vertical: AppSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: tierColor(
                                      context,
                                      lp.proficiencyLevel,
                                    ).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(
                                      AppRadius.lg,
                                    ),
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
                                      const SizedBox(width: AppSpacing.xs),
                                      Text(
                                        lp.proficiencyLevel,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: tierColor(
                                                context,
                                                lp.proficiencyLevel,
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      // Chosen, not yet confirmed by a test.
                                      if (!lp.levelVerified) ...[
                                        const SizedBox(width: AppSpacing.xs),
                                        Tooltip(
                                          message:
                                              'profile.levelUnverifiedValue'.tr(
                                                namedArgs: {
                                                  'level': lp.proficiencyLevel,
                                                  'certified':
                                                      lp.certifiedLevel,
                                                },
                                              ),
                                          child: Icon(
                                            Icons.help_outline_rounded,
                                            size: 14,
                                            color: tierColor(
                                              context,
                                              lp.proficiencyLevel,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                              // League Rank Badge
                              TapTarget(
                                onTap: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const LeaderboardScreen(),
                                  ),
                                ),
                                child: isMasterRank
                                    ? ShaderMask(
                                        shaderCallback: (bounds) =>
                                            const LinearGradient(
                                              colors: AppColors.masterGradient,
                                              begin: Alignment.topLeft,
                                              end: Alignment.bottomRight,
                                            ).createShader(bounds),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.onGradient
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              AppRadius.lg,
                                            ),
                                            border: Border.all(
                                              color: AppColors.onGradient
                                                  .withValues(alpha: 0.4),
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
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color:
                                                          AppColors.onGradient,
                                                      fontWeight:
                                                          FontWeight.bold,
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
                                          borderRadius: BorderRadius.circular(
                                            20,
                                          ),
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
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: rankData.color,
                                                    fontWeight: FontWeight.bold,
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
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        formatMemberSince(context, user?.createdAt),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: AppColorRoles.textSecondary(isDark),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      // Edit Profile Button
                      TapTarget(
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
                            vertical: AppSpacing.sm,
                          ),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: AppColorRoles.primaryGradient(isDark),
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    (isDark
                                            ? accent
                                            : Theme.of(
                                                context,
                                              ).colorScheme.primary)
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
                              Flexible(
                                child: Text(
                                  'profile.editProfile'.tr(),
                                  style: Theme.of(context).textTheme.bodySmall
                                      ?.copyWith(
                                        color: AppColors.surfaceLight,
                                        fontWeight: FontWeight.bold,
                                      ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      // Social Stats Row
                      const SocialStatsRow(),
                    ],
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
