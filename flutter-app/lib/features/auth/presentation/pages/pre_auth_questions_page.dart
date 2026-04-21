import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/language_switcher_button.dart';

/// Answers collected during the pre-authentication onboarding flow.
class PreAuthAnswers {
  final String name;
  final String nativeLanguage;

  const PreAuthAnswers({required this.name, required this.nativeLanguage});

  Map<String, dynamic> toJson() => {
        'name': name,
        'native_language': nativeLanguage,
      };

  factory PreAuthAnswers.fromJson(Map<String, dynamic> json) => PreAuthAnswers(
        name: json['name'] as String? ?? '',
        nativeLanguage: json['native_language'] as String? ?? 'vi',
      );
}

class PreAuthQuestionsPage extends StatefulWidget {
  final void Function(PreAuthAnswers answers) onComplete;
  final VoidCallback onBack;

  const PreAuthQuestionsPage({
    super.key,
    required this.onComplete,
    required this.onBack,
  });

  @override
  State<PreAuthQuestionsPage> createState() => _PreAuthQuestionsPageState();
}

class _PreAuthQuestionsPageState extends State<PreAuthQuestionsPage>
    with TickerProviderStateMixin {
  final PageController _pageController = PageController();
  final TextEditingController _nameController = TextEditingController();

  int _currentPage = 0;
  String _selectedLanguage = 'vi';
  String _nameError = '';

  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  static const int _totalPages = 2;

  static const List<_LangOption> _languages = [
    _LangOption('vi', 'Tiếng Việt', '🇻🇳'),
    _LangOption('en', 'English', '🇺🇸'),
    _LangOption('ja', '日本語', '🇯🇵'),
    _LangOption('ko', '한국어', '🇰🇷'),
    _LangOption('zh', '中文', '🇨🇳'),
    _LangOption('fr', 'Français', '🇫🇷'),
    _LangOption('es', 'Español', '🇪🇸'),
    _LangOption('other', 'Other', '🌍'),
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _nameController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  void _goNext() {
    if (_currentPage == 0) {
      final trimmed = _nameController.text.trim();
      if (trimmed.isEmpty) {
        setState(() => _nameError = 'Please enter your name');
        return;
      }
      setState(() => _nameError = '');
    }

    if (_currentPage < _totalPages - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onComplete(
        PreAuthAnswers(
          name: _nameController.text.trim(),
          nativeLanguage: _selectedLanguage,
        ),
      );
    }
  }

  void _goBack() {
    if (_currentPage > 0) {
      _pageController.previousPage(
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    } else {
      widget.onBack();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor:
          isDark ? AppColors.accentMintDark : AppColors.backgroundLight,
      body: FadeTransition(
        opacity: _fadeAnimation,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Top bar
                Row(
                  children: [
                    IconButton(
                      onPressed: _goBack,
                      icon: Icon(
                        Icons.arrow_back_rounded,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        'Quick Setup',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.white : AppColors.textDark,
                        ),
                      ),
                    ),
                    Text(
                      '${_currentPage + 1}/$_totalPages',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: isDark ? Colors.white60 : AppColors.textSlate,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const LanguageSwitcherButton(),
                  ],
                ),
                const SizedBox(height: 10),
                // Progress bar
                ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    value: (_currentPage + 1) / _totalPages,
                    minHeight: 6,
                    backgroundColor:
                        isDark ? AppColors.slate800 : AppColors.slate200,
                    valueColor: const AlwaysStoppedAnimation(
                      AppColors.accentMint,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                // Pages
                Expanded(
                  child: PageView(
                    controller: _pageController,
                    physics: const NeverScrollableScrollPhysics(),
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                    },
                    children: [
                      _buildNameStep(context, isDark, theme),
                      _buildLanguageStep(context, isDark, theme),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                // Continue button
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _goNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentMint,
                      foregroundColor: AppColors.accentMintDark,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      _currentPage < _totalPages - 1
                          ? 'Continue'
                          : 'Create My Account',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
                if (_currentPage == _totalPages - 1) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: () => widget.onComplete(
                        PreAuthAnswers(
                          name: _nameController.text.trim(),
                          nativeLanguage: _selectedLanguage,
                        ),
                      ),
                      child: Text(
                        'auth.alreadyHaveAccount'.tr(),
                        style: TextStyle(
                          color: isDark
                              ? Colors.white60
                              : AppColors.textSlate,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNameStep(
      BuildContext context, bool isDark, ThemeData theme) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 20),
          // Icon
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.accentMint.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline_rounded,
                size: 44,
                color: AppColors.accentMint,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'What should we call you?',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : AppColors.textDark,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'This will be your display name in the app.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: isDark ? Colors.white60 : AppColors.textGrey,
            ),
          ),
          const SizedBox(height: 32),
          TextField(
            controller: _nameController,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: isDark ? Colors.white : AppColors.textDark,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: 'Your name',
              hintStyle: TextStyle(
                color: isDark ? Colors.white38 : AppColors.textGrey,
              ),
              prefixIcon: const Icon(
                Icons.badge_outlined,
                color: AppColors.accentMint,
              ),
              errorText: _nameError.isNotEmpty ? _nameError : null,
              filled: true,
              fillColor: isDark
                  ? AppColors.slate800.withOpacity(0.6)
                  : Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(
                  color: AppColors.accentMint,
                  width: 2,
                ),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 16,
              ),
            ),
            onSubmitted: (_) => _goNext(),
          ),
          const SizedBox(height: 16),
          Text(
            'You can always change this later in your profile.',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.white38 : AppColors.textGrey,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLanguageStep(
      BuildContext context, bool isDark, ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 8),
        Text(
          'What is your native language?',
          textAlign: TextAlign.center,
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : AppColors.textDark,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          "We'll use this to tailor hints and explanations for you.",
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: isDark ? Colors.white60 : AppColors.textGrey,
          ),
        ),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 2.4,
            children: _languages.map((lang) {
              final isSelected = _selectedLanguage == lang.code;
              return GestureDetector(
                onTap: () => setState(() => _selectedLanguage = lang.code),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? AppColors.accentMint.withOpacity(0.2)
                        : isDark
                            ? AppColors.slate800.withOpacity(0.5)
                            : Colors.white,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.accentMint
                          : isDark
                              ? AppColors.slate800
                              : AppColors.slate200,
                      width: isSelected ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        lang.flag,
                        style: const TextStyle(fontSize: 22),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          lang.label,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: isSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: isSelected
                                ? AppColors.accentMint
                                : isDark
                                    ? Colors.white
                                    : AppColors.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSelected) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.check_circle_rounded,
                          color: AppColors.accentMint,
                          size: 18,
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _LangOption {
  final String code;
  final String label;
  final String flag;

  const _LangOption(this.code, this.label, this.flag);
}
