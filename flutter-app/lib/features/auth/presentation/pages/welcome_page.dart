import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/language_switcher_button.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Get Started page for first-time visitors before authentication.
class WelcomePage extends StatefulWidget {
  final VoidCallback onGetStarted;
  final VoidCallback onSkip;
  final String? userName;

  const WelcomePage({
    super.key,
    required this.onGetStarted,
    required this.onSkip,
    this.userName,
  });

  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.accentMintDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: FadeTransition(
            opacity: CurvedAnimation(
              parent: _controller,
              curve: Curves.easeOut,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
                    child: Row(
                      children: [
                        Semantics(
                          button: true,
                          label: 'common.language'.tr(),
                          child: TapTarget(
                            onTap: () =>
                                LanguageSwitcherButton.showLanguageSheet(
                                  context,
                                ),
                            child: Container(
                              height: 40,
                              width: 40,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF30E8E8,
                                ).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: const Icon(
                                Icons.language,
                                color: AppColors.accentMint,
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              'assets/out-app/lexilingo-text.png',
                              height: 64,
                              fit: BoxFit.contain,
                            ),
                          ),
                        ),
                        const SizedBox(width: 40),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.xs,
                        AppSpacing.lg,
                        20,
                      ),
                      child: Column(
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.xl),
                              child: Image.asset(
                                'assets/out-app/banner-start.png',
                                fit: BoxFit.contain,
                              ),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Text(
                            'onboarding.welcome'.tr(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDark
                                  ? AppColors.onGradient
                                  : AppColors.surfaceDarkInput,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'app.tagline'.tr(),
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: isDark
                                  ? Colors.white70
                                  : Theme.of(
                                      context,
                                    ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: FilledButton.icon(
                              onPressed: widget.onGetStarted,
                              icon: const Icon(Icons.arrow_forward),
                              label: Text(
                                'onboarding.getStarted'.tr(),
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.accentMint,
                                foregroundColor: AppColors.accentMintDark,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          SizedBox(
                            width: double.infinity,
                            height: 56,
                            child: OutlinedButton(
                              onPressed: widget.onSkip,
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Color(0x4430E8E8),
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppRadius.md,
                                  ),
                                ),
                              ),
                              child: Text(
                                'auth.alreadyHaveAccount'.tr(),
                                style: TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildStatItem(
                                context,
                                'onboarding.activeUsers'.tr(),
                                '50k+',
                              ),
                              const SizedBox(width: 20),
                              _buildStatItem(
                                context,
                                'onboarding.dailyLessons'.tr(),
                                '12k+',
                              ),
                            ],
                          ),
                          const SizedBox(height: 14),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _buildAvatar(
                                'https://lh3.googleusercontent.com/aida-public/AB6AXuAueXEdJeOZP5A67AihhrKDRfhgW8loPOC8jRC2TVq4eYU7UGPToFFwKjwji8yJCkd9mLJ6NVYtLxlxvwjenledwX8QGN0skcWfziNqe-suZMfvNeSsviHWd72OZkgCUWZpzskPpX7ibik2bF2aHwGdMGWSWHcu11-Z3XUAfGKYQVkdrDc9teq34cTsWYFv-KSCEsOJ8McOBldBez5n-gIcve820LP33S1bgUjI89FXKibiWinvy40_o8ccXdOtt_3LxZDni5bAM_I',
                              ),
                              Transform.translate(
                                offset: const Offset(-10, 0),
                                child: _buildAvatar(
                                  'https://lh3.googleusercontent.com/aida-public/AB6AXuCUJVqOVKOza-lu-MYOLBITNBKO9yp182dMoHgnnuOmLtMbkZ0Er6cVCea5-Q3UqnAqM6FDM-DWURgu7CckXI6dU0lhYSBfL7P19wFwrmpYhkXHmF0nVOxKoww9oQm7YAjZZTquShpE4baE5nvSmSO7HD26DC6G_V00Trxecp8a7MLdcPn_u88CynqhkLE96mviJCUIoQK3bc_WO2nDZGt5CRYI0hL0r_LPwh9so8XN_NETyH4ILKxZKYm4qOEJVdP9G3GmIP8od5M',
                                ),
                              ),
                              Transform.translate(
                                offset: const Offset(-20, 0),
                                child: _buildAvatar(
                                  'https://lh3.googleusercontent.com/aida-public/AB6AXuDh8w9mHRMsKUobp8aWGqHZ6LXaOhoFOEUKCtsCii3VAtwJ1dru5bV3TQmgY2th7h3XUiqCgytuEmX0QpvJuw7SGDjbFRMYnrIhUJGoPGjveUPiBOtBsJb_EzeFHClWbFIeLtFDAyIQAiYAYTGyu4qy3j9Pm7Vc9LUpvzFWn5Evm_DrjsioVgYlxaZFwso-vTgvsdnPYB2vreATNgeOVQPxS1DFpbXSUSFQ7RuF5oO20KOeONIEz5PEDrxZ09B_mm7RNbGAy_HdUHE',
                                ),
                              ),
                              Flexible(
                                child: Text(
                                  'onboarding.globalCommunity'.tr(),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: isDark
                                        ? AppColors.textMuted
                                        : Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: isDark
                ? AppColors.textMuted
                : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? AppColors.onGradient : const Color(0xFF334155),
          ),
        ),
      ],
    );
  }

  Widget _buildAvatar(String url) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        border: Border.all(
          color: Theme.of(context).colorScheme.surface,
          width: 1.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (context, _, __) => const ColoredBox(
          color: Color(0x2230E8E8),
          child: Icon(Icons.person, size: 18),
        ),
      ),
    );
  }
}
