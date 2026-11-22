import 'package:lexilingo_app/core/l10n/relative_time.dart';
import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/gamification/presentation/theme/reward_palette.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/gamification/presentation/providers/gamification_provider.dart';
import 'package:lexilingo_app/features/gamification/domain/entities/wallet.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';

/// Wallet Screen
/// Displays gem balance and transaction history
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GamificationProvider>();
      provider.loadWallet();
      provider.loadTransactions();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: Consumer<GamificationProvider>(
          builder: (context, provider, child) {
            return CustomScrollView(
              slivers: [
                // App Bar with balance
                SliverAppBar(
                  expandedHeight: 200,
                  pinned: true,
                  flexibleSpace: FlexibleSpaceBar(
                    background: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: RewardPalette.walletGradient,
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                      ),
                      child: SafeArea(
                        bottom: false,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 40),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Gem icon
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppColors.surfaceLight.withValues(
                                    alpha: 0.18,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: AppColors.surfaceLight.withValues(
                                      alpha: 0.35,
                                    ),
                                    width: 1.5,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.diamond_rounded,
                                  color: AppColors.surfaceLight,
                                  size: 34,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.sm),
                              // Balance — animates to the new total on change.
                              if (provider.wallet == null)
                                Semantics(
                                  label:
                                      (provider.walletUnavailable
                                              ? 'errors.loadFailed'
                                              : 'common.loading')
                                          .tr(),
                                  child: Text(
                                    '—',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.surfaceLight,
                                        ),
                                  ),
                                )
                              else
                                // No begin: the first build shows the balance
                                // as is, later changes tween from the old one.
                                TweenAnimationBuilder<int>(
                                  tween: IntTween(end: provider.gems),
                                  duration: const Duration(milliseconds: 600),
                                  curve: Curves.easeOutCubic,
                                  builder: (_, value, __) => Text(
                                    '$value',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displaySmall
                                        ?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.surfaceLight,
                                        ),
                                  ),
                                ),
                              const SizedBox(height: 2),
                              Text(
                                'gamification.gems'.tr(),
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: AppColors.surfaceLight.withValues(
                                        alpha: 0.75,
                                      ),
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 1.2,
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                // Stats Row
                SliverToBoxAdapter(
                  child: Container(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: provider.walletUnavailable
                        ? ErrorDisplayWidget.fromMessage(
                            message: 'errors.loadFailed'.tr(),
                            onRetry: provider.loadWallet,
                            compact: true,
                          )
                        : Row(
                            children: [
                              Expanded(
                                child: _buildStatCard(
                                  icon: Icons.arrow_upward,
                                  color: AppColors.greenSuccessBright,
                                  label: 'gamification.earned'.tr(),
                                  value:
                                      provider.wallet?.totalEarned.toString() ??
                                      '—',
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: _buildStatCard(
                                  icon: Icons.arrow_downward,
                                  color: AppColors.orange,
                                  label: 'gamification.spent'.tr(),
                                  value:
                                      provider.wallet?.totalSpent.toString() ??
                                      '—',
                                ),
                              ),
                            ],
                          ),
                  ),
                ),

                // How to earn section
                SliverToBoxAdapter(
                  child: Container(
                    margin: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.purpleGradient[0].withValues(alpha: 0.10),
                          AppColors.purpleGradient[1].withValues(alpha: 0.05),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(AppRadius.lg),
                      border: Border.all(
                        color: AppColors.purpleGradient[0].withValues(
                          alpha: 0.25,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: AppColors.purpleGradient[0].withValues(
                                  alpha: 0.18,
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: Icon(
                                Icons.diamond_rounded,
                                color: AppColors.purpleGradient[0],
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.md),
                            Flexible(
                              child: Text(
                                'gamification.howToEarnGems'.tr(),
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.md),
                        _buildEarnTip(
                          'gamification.earnTipCompleteLessons'.tr(),
                          '+5 gems',
                        ),
                        _buildEarnTip(
                          'gamification.earnTipFinishCourse'.tr(),
                          '+50 gems',
                        ),
                        _buildEarnTip(
                          'gamification.earnTipStreakBonus'.tr(),
                          '+3 gems',
                        ),
                        _buildEarnTip(
                          'gamification.earnTipAchievements'.tr(),
                          '+10-100 gems',
                        ),
                        _buildEarnTip(
                          'gamification.earnTipChallenges'.tr(),
                          '+20 gems',
                        ),
                      ],
                    ),
                  ),
                ),

                // Transaction History Header
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            'gamification.transactionHistory'.tr(),
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              provider.loadTransactions(limit: 100),
                          child: Text('common.seeAll'.tr()),
                        ),
                      ],
                    ),
                  ),
                ),

                // Transaction List
                if (provider.transactions.isEmpty)
                  SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xxl),
                        child: Column(
                          children: [
                            Icon(
                              Icons.receipt_long_outlined,
                              size: 48,
                              color: AppColors.grey400,
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Text(
                              'gamification.noTransactions'.tr(),
                              style: TextStyle(color: AppColors.grey600),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  SliverList(
                    delegate: SliverChildBuilderDelegate((context, index) {
                      final transaction = provider.transactions[index];
                      return _TransactionRow(transaction: transaction);
                    }, childCount: provider.transactions.length),
                  ),

                // Bottom padding
                const SliverToBoxAdapter(child: SizedBox(height: 80)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withValues(alpha: 0.05),
            blurRadius: 8,
          ), // scrim, not brand color
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.grey600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEarnTip(String label, String reward) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            color: AppColors.purpleGradient[0],
            size: 16,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              label,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AppColors.grey700),
            ),
          ),
          Text(
            reward,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: AppColors.purpleGradient[1],
            ),
          ),
        ],
      ),
    );
  }
}

/// Transaction Row Widget
class _TransactionRow extends StatelessWidget {
  final WalletTransactionEntity transaction;

  const _TransactionRow({required this.transaction});

  @override
  Widget build(BuildContext context) {
    final isEarning = transaction.isEarning;
    final color = isEarning ? AppColors.greenSuccessBright : AppColors.orange;

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.grey500.withValues(alpha: 0.1)),
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(_getTransactionIcon(), color: color, size: 20),
          ),
          const SizedBox(width: AppSpacing.md),

          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.description,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w500),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _formatDate(transaction.createdAt),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: AppColors.grey500),
                ),
              ],
            ),
          ),

          // Amount
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              children: [
                Icon(
                  isEarning ? Icons.add : Icons.remove,
                  size: 14,
                  color: color,
                ),
                const SizedBox(width: 2),
                Text(
                  '${transaction.amount}',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: color,
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Icon(Icons.diamond, size: 12, color: color),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _getTransactionIcon() {
    switch (transaction.referenceType) {
      case 'achievement':
        return Icons.emoji_events;
      case 'purchase':
        return Icons.shopping_bag;
      case 'challenge':
        return Icons.flag;
      case 'lesson':
        return Icons.menu_book;
      case 'streak':
        return Icons.local_fire_department;
      default:
        return transaction.isEarning ? Icons.add_circle : Icons.remove_circle;
    }
  }

  String _formatDate(DateTime date) => relativeTime(date);
}
