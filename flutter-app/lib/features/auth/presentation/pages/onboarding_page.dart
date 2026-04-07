import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class OnboardingAnswers {
  final String goal;
  final String level;
  final String interest;

  const OnboardingAnswers({
    required this.goal,
    required this.level,
    required this.interest,
  });

  Map<String, dynamic> toJson() {
    return {'goal': goal, 'level': level, 'interest': interest};
  }
}

class OnboardingPage extends StatefulWidget {
  final Future<void> Function(OnboardingAnswers answers) onComplete;

  const OnboardingPage({super.key, required this.onComplete});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final PageController _pageController = PageController();

  int _currentPage = 0;
  bool _isSubmitting = false;

  String _selectedGoal = 'career';
  String _selectedLevel = 'A1';
  String _selectedInterest = 'daily-life';

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _goNext() async {
    if (_currentPage < 2) {
      await _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await widget.onComplete(
        OnboardingAnswers(
          goal: _selectedGoal,
          level: _selectedLevel,
          interest: _selectedInterest,
        ),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF112121)
          : const Color(0xFFF6F8F8),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                children: [
                  Text(
                    'Personalize your learning',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_currentPage + 1}/3',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: isDark ? Colors.white70 : const Color(0xFF475569),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: (_currentPage + 1) / 3,
                  minHeight: 8,
                  backgroundColor: isDark
                      ? const Color(0xFF1F2937)
                      : const Color(0xFFE2E8F0),
                  valueColor: const AlwaysStoppedAnimation(AppColors.accentMint),
                ),
              ),
              const SizedBox(height: 18),
              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (index) {
                    setState(() => _currentPage = index);
                  },
                  children: [
                    _buildGoalGridStep(
                      context: context,
                      title: 'What is your goal?',
                      subtitle: 'We\'ll tailor your learning experience based on your choice.',
                      value: _selectedGoal,
                      onSelected: (value) {
                        setState(() => _selectedGoal = value);
                      },
                    ),
                    _buildChoiceStep(
                      context: context,
                      title: 'What is your current level?',
                      subtitle:
                          'This helps us set content difficulty from the start.',
                      value: _selectedLevel,
                      options: const [
                        _OnboardingOption('A1', 'A1 - Beginner', Icons.child_care_rounded),
                        _OnboardingOption('A2', 'A2 - Elementary', Icons.directions_walk_rounded),
                        _OnboardingOption('B1', 'B1 - Intermediate', Icons.directions_run_rounded),
                        _OnboardingOption('B2', 'B2 - Upper Intermediate', Icons.directions_bike_rounded),
                        _OnboardingOption('C1', 'C1 - Advanced', Icons.workspace_premium_rounded),
                      ],
                      onSelected: (value) {
                        setState(() => _selectedLevel = value);
                      },
                    ),
                    _buildChoiceStep(
                      context: context,
                      title: 'What topics do you like most?',
                      subtitle:
                          'We will prioritize lessons around your interests.',
                      value: _selectedInterest,
                      options: const [
                        _OnboardingOption(
                          'daily-life',
                          'Daily life & social topics',
                          Icons.coffee_rounded
                        ),
                        _OnboardingOption(
                          'technology',
                          'Technology & innovation',
                          Icons.computer_rounded
                        ),
                        _OnboardingOption('culture', 'Culture & entertainment', Icons.palette_rounded),
                        _OnboardingOption(
                          'career',
                          'Career growth & interviews',
                          Icons.business_center_rounded
                        ),
                      ],
                      onSelected: (value) {
                        setState(() => _selectedInterest = value);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _goNext,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.accentMint,
                    foregroundColor: const Color(0xFF112121),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.2),
                        )
                      : Text(
                          _currentPage < 2 ? 'Continue' : 'Create My Plan',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }


  Widget _buildGoalGridStep({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required ValueChanged<String> onSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final goals = [
      {
        'id': 'career',
        'label': 'Career',
        'icon': Icons.work_outline_rounded,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBSGVTCqylquusN6wGLM_jOvQqZQSuWDjlL-xpyq_2UqBLnr-OByxFEoIsMmggErKwNxosf8XQfnZD1eOVm9caqCYFt05Vh9s94Fn-qplqqhm7a88oozanlytpKwXzKQY4uL6OQEKICN_GEKFKELHvJi_cXq30k9_2eZPpZs3eRonNJhAHVNgOClJeuq0KKKLQykpcHW76NUlAIUOoXBXDSABIrOkJFXYD06oyY5toJFdWSBgQUPG90eJY5ifIrfBZXGY4ELJOVrWo',
      },
      {
        'id': 'travel',
        'label': 'Travel',
        'icon': Icons.flight_takeoff_rounded,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuDs7YS8V0VzuKvGJMR3ApIBaJyOCi2ZqtcHHuf051ELU2SVqSFJeNb6D_GVRXzyKX0qUNzG8nvSegEBBRVqyryZtY_GvGiJoe7SUrzcr3o_iZWnWq-GK_gaCJmwTyepSWQGpkgztvxfL64H9BdF-8T18jx6wfCiajnZsud2H19FBD9SZDIjYG--ITayp8d_X-TvJwKCFeHURrHsXO4YcAQw2avpqGQOAMDi-9oXnro_TKg97Xx6ksqFh5x-YTJqCIG-Z_1pD_f4kuI',
      },
      {
        'id': 'exam',
        'label': 'Exams',
        'icon': Icons.menu_book_rounded,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuBCuJx8wfZGG_xbA24mGPi6yv8NQG8CSAvF65QQ3kdvG4K8Oui7yCqIhEvlt-LBa8Xb-Mj23nY7K7zK2BLiZfSB2pZxisXv5e4nL2Kz8TuYsVySB8J4sLnqa-pvJNZz3dsRiSsBv4P1iogZPm5b80saHzpefwNpyDZny2zJ_dOMTEEWrXQg32UErPs8ZKvNjKWsQrc-l1HHTEFvJSd4krbaTs3pNIB1Iz-svOzhvxy3FuhlA26vxzptUIew5jIQ4je18KgT34_R5Og',
      },
      {
        'id': 'culture',
        'label': 'Culture',
        'icon': Icons.theater_comedy_rounded,
        'image':
            'https://lh3.googleusercontent.com/aida-public/AB6AXuDsX3m4bn2ZpAMoVNcHDZThQaKBGp2tTg2oh1O_uPSbPUvHkkHqEB0f6ji6OFFn85oWNCybtS_5QWPat9X0ADsYcafwBfW0R-GVkmjZzhlCiuWlHLvqu9Ft_03QouejdaijcnxmU1cPRwoGm634qW1UM9kEpALf0YLouTvJn2BHGgzQEk8g1xz5toJAR8JDM3RUtZ7mjHraJ3L6ABIOzCGcpFwPjA1UDa2pa9tQTtz8Qiw3ofb6ydW3gTkr1X69p0KMMGLa2PkmbHA',
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 28,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : AppColors.textGrey,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 24),
        Expanded(
          child: GridView.builder(
            physics: const BouncingScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 1.0,
            ),
            itemCount: goals.length,
            itemBuilder: (context, index) {
              final goal = goals[index];
              final isSelected = value == goal['id'];

              return GestureDetector(
                onTap: () => onSelected(goal['id'] as String),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accentMint
                          : Colors.transparent,
                      width: 2,
                    ),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: AppColors.accentMint.withValues(alpha: 0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : null,
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          goal['image'] as String,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              color: isDark ? const Color(0xFF1F2937) : const Color(0xFFE2E8F0),
                            );
                          },
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.8),
                                Colors.black.withValues(alpha: 0.0),
                              ],
                              stops: const [0.0, 0.6],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.end,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AnimatedOpacity(
                                duration: const Duration(milliseconds: 300),
                                opacity: isSelected ? 1.0 : 0.0,
                                child: Icon(
                                  goal['icon'] as IconData,
                                  color: AppColors.accentMint,
                                  size: 28,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                goal['label'] as String,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Widget _buildChoiceStep({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String value,
    required List<_OnboardingOption> options,
    required ValueChanged<String> onSelected,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            fontSize: 28,
            color: isDark ? Colors.white : AppColors.textDark,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white70 : AppColors.textGrey,
            fontSize: 15,
          ),
        ),
        const SizedBox(height: 32),
        Expanded(
          child: ListView.separated(
            physics: const BouncingScrollPhysics(),
            itemBuilder: (context, index) {
              final option = options[index];
              final selected = value == option.value;

              return GestureDetector(
                onTap: () => onSelected(option.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: selected
                        ? AppColors.accentMint.withValues(alpha: 0.1)
                        : (isDark
                              ? const Color(0xFF0F172A).withValues(alpha: 0.55)
                              : Colors.white),
                    border: Border.all(
                      color: selected
                          ? AppColors.accentMint
                          : (isDark
                                ? const Color(0xFF334155).withValues(alpha: 0.5)
                                : const Color(0xFFE2E8F0)),
                      width: selected ? 2 : 1.5,
                    ),
                    boxShadow: selected
                        ? [
                            BoxShadow(
                              color: AppColors.accentMint.withValues(alpha: 0.2),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.02),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            )
                          ],
                  ),
                  child: Row(
                    children: [
                      if (option.icon != null) ...[
                        Icon(
                          option.icon,
                          color: selected ? AppColors.accentMint : (isDark ? Colors.white54 : AppColors.textGrey),
                          size: 26,
                        ),
                        const SizedBox(width: 16),
                      ],
                      Expanded(
                        child: Text(
                          option.label,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: selected 
                                ? (isDark ? Colors.white : AppColors.textDark)
                                : (isDark ? Colors.white70 : const Color(0xFF475569)),
                            fontSize: 17,
                          ),
                        ),
                      ),
                      AnimatedScale(
                        scale: selected ? 1.1 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected ? AppColors.accentMint : (isDark ? Colors.white24 : const Color(0xFFCBD5E1)),
                              width: selected ? 6 : 2,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
            separatorBuilder: (_, __) => const SizedBox(height: 16),
            itemCount: options.length,
          ),
        ),
      ],
    );
  }
}

class _OnboardingOption {
  final String value;
  final String label;
  final IconData? icon;

  const _OnboardingOption(this.value, this.label, [this.icon]);
}
