import 'package:easy_localization/easy_localization.dart';
import '../../../ielts/presentation/pages/ielts_tests_page.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/premium_gate.dart';
import 'package:lexilingo_app/core/services/purchases_service.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/practice/presentation/widgets/practice_lab_models.dart';
import 'package:lexilingo_app/features/practice/presentation/widgets/practice_lab_navigation.dart';
import 'package:provider/provider.dart';

class PracticeLabPage extends StatefulWidget {
  const PracticeLabPage({super.key});

  @override
  State<PracticeLabPage> createState() => _PracticeLabPageState();
}

class _PracticeLabPageState extends State<PracticeLabPage> {
  // Drives which cards may be recommended. Assume no entitlement until the
  // check answers, so a free learner is never shown a locked card as their
  // top suggestion while it resolves.
  bool _hasPremium = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ProficiencyProvider>().loadProfile();
    });
    _loadPremiumStatus();
  }

  Future<void> _loadPremiumStatus() async {
    try {
      final isPremium = await PurchasesService.instance.isPremium;
      if (!mounted || isPremium == _hasPremium) return;
      setState(() => _hasPremium = isPremium);
    } catch (_) {
      // Entitlement unknown — leave it locked rather than promoting a card
      // the learner may not be able to open.
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(title: Text('practiceLab.title'.tr())),
      body: SafeArea(
        child: Consumer<ProficiencyProvider>(
          builder: (context, proficiency, _) {
            final items = buildPracticeLabItems(
              weakestSkills: proficiency.weakestSkills,
            );
            final recommended = recommendedPracticeItems(
              items: items,
              hasPremium: _hasPremium,
            );
            final hasRecommendations = items.any((item) => item.recommended);

            return RefreshIndicator(
              onRefresh: proficiency.loadProfile,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _PracticeLabHero(
                    levelCode: proficiency.levelCode,
                    recommendedCount: hasRecommendations
                        ? recommended.length
                        : 0,
                    isLoading: proficiency.isLoading,
                  ),
                  const SizedBox(height: 16),
                  const _IeltsEntryCard(),
                  const SizedBox(height: 16),
                  _SectionHeader(
                    title: 'practiceLab.recommendedTitle'.tr(),
                    subtitle: hasRecommendations
                        ? 'practiceLab.recommendedSubtitle'.tr()
                        : 'practiceLab.fallbackSubtitle'.tr(),
                  ),
                  const SizedBox(height: 10),
                  for (final item in recommended) ...[
                    _PracticeLabCardGate(
                      item: item,
                      compact: true,
                      onTap: () => openPracticeLabItem(context, item),
                    ),
                    const SizedBox(height: 10),
                  ],
                  const SizedBox(height: 8),
                  _SectionHeader(
                    title: 'practiceLab.allSkillsTitle'.tr(),
                    subtitle: 'practiceLab.allSkillsSubtitle'.tr(),
                  ),
                  const SizedBox(height: 10),
                  for (final item in items) ...[
                    _PracticeLabCardGate(
                      item: item,
                      onTap: () => openPracticeLabItem(context, item),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PracticeLabCardGate extends StatelessWidget {
  const _PracticeLabCardGate({
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final PracticeLabItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final card = _PracticeLabSkillCard(
      item: item,
      compact: compact,
      onTap: onTap,
    );

    if (!item.premiumOnly) return card;

    return PremiumGate(
      lockedChild: _LockedPracticeLabCard(item: item, compact: compact),
      child: card,
    );
  }
}

class _PracticeLabHero extends StatelessWidget {
  const _PracticeLabHero({
    required this.levelCode,
    required this.recommendedCount,
    required this.isLoading,
  });

  final String levelCode;
  final int recommendedCount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.science_rounded, color: accent, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'practiceLab.heroTitle'.tr(),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'practiceLab.heroSubtitle'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeroMetric(
                  label: 'practiceLab.currentLevel'.tr(),
                  value: levelCode,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroMetric(
                  label: 'practiceLab.recommended'.tr(),
                  value: isLoading ? '...' : '$recommendedCount',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroMetric extends StatelessWidget {
  const _HeroMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkInput : AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: AppColorRoles.textSecondary(isDark),
            height: 1.3,
          ),
        ),
      ],
    );
  }
}

class _PracticeLabSkillCard extends StatelessWidget {
  const _PracticeLabSkillCard({
    required this.item,
    required this.onTap,
    this.compact = false,
  });

  final PracticeLabItem item;
  final VoidCallback onTap;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDarkMuted : Colors.white;
    final borderColor = item.recommended
        ? item.color.withValues(alpha: isDark ? 0.65 : 0.45)
        : isDark
        ? AppColors.borderDarkSoft
        : AppColors.slate200;

    return Material(
      color: surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: EdgeInsets.all(compact ? 14 : 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: compact ? 44 : 50,
                height: compact ? 44 : 50,
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  item.icon,
                  color: item.color,
                  size: compact ? 22 : 25,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.titleKey.tr(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.w900),
                          ),
                        ),
                        if (item.recommended) ...[
                          const SizedBox(width: 8),
                          _RecommendedPill(color: item.color),
                        ],
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.subtitleKey.tr(),
                      maxLines: compact ? 1 : 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
                        height: 1.3,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _SmallChip(
                          icon: Icons.schedule_rounded,
                          label: item.estimateKey.tr(),
                        ),
                        _SmallChip(
                          icon: Icons.play_arrow_rounded,
                          label: item.actionKey.tr(),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                Icons.chevron_right_rounded,
                color: AppColorRoles.textSecondary(isDark),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockedPracticeLabCard extends StatelessWidget {
  const _LockedPracticeLabCard({required this.item, required this.compact});

  final PracticeLabItem item;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = isDark ? AppColors.surfaceDarkMuted : Colors.white;

    return Container(
      padding: EdgeInsets.all(compact ? 14 : 16),
      decoration: BoxDecoration(
        color: surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.gold.withValues(alpha: isDark ? 0.65 : 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: compact ? 44 : 50,
            height: compact ? 44 : 50,
            decoration: BoxDecoration(
              color: AppColors.gold.withValues(alpha: isDark ? 0.18 : 0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.workspace_premium_rounded,
              color: AppColors.goldDark,
              size: 25,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.titleKey.tr(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        'practiceLab.premiumOnly'.tr(),
                        style: const TextStyle(
                          color: AppColors.goldDark,
                          fontWeight: FontWeight.w900,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  'practiceLab.premiumLockedSubtitle'.tr(),
                  maxLines: compact ? 1 : 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColorRoles.textSecondary(isDark),
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 10),
                _SmallChip(
                  icon: Icons.lock_open_rounded,
                  label: 'practiceLab.unlockPremium'.tr(),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Icon(
            Icons.chevron_right_rounded,
            color: AppColorRoles.textSecondary(isDark),
          ),
        ],
      ),
    );
  }
}

class _RecommendedPill extends StatelessWidget {
  const _RecommendedPill({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        'practiceLab.focus'.tr(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w900,
          fontSize: 11,
        ),
      ),
    );
  }
}

class _SmallChip extends StatelessWidget {
  const _SmallChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkInput : AppColors.grey100,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: AppColorRoles.textSecondary(isDark)),
          const SizedBox(width: 5),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}


/// Entry point to the IELTS mock tests.
///
/// Deliberately a card of its own rather than a `PracticeLabItem`: a mock test
/// is a one-to-three-hour sitting covering all four skills, so it does not
/// belong in a list of per-skill drills the recommender ranks.
class _IeltsEntryCard extends StatelessWidget {
  const _IeltsEntryCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const IeltsTestsPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.school_outlined,
                  color: theme.colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'IELTS mock tests',
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Full four-skill papers, scored in bands with AI feedback on Writing and Speaking.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.chevron_right,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
