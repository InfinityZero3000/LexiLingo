import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/user/presentation/providers/settings_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:lexilingo_app/core/theme/app_tactile_theme.dart';
import '../providers/auth_provider.dart';
import '../../../home/presentation/pages/main_screen.dart';
import '../pages/login_page.dart';
import '../pages/register_page.dart';
import '../pages/welcome_page.dart';
import '../pages/onboarding_page.dart';
import '../pages/pre_auth_questions_page.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _showOnboarding = false;
  bool _showPreAuthWelcome = false;
  bool _showPreAuthQuestions = false;
  bool _wasAuthenticated = false;
  bool _isResolvingFlow = false;
  bool _isResolvingPreAuthFlow = false;
  bool _isShowingRegister = false;
  bool _preAuthFlowResolved = false;
  String? _flowResolvedForUserId;
  PreAuthAnswers? _pendingPreAuthAnswers;

  static const String _preAuthAnswersKey = 'pre_auth_answers_pending';

  String _onboardingCompletedKey(String userId) =>
      '${AppConstants.firstTimeUserKey}_completed_$userId';
  String _onboardingConfigKey(String userId) =>
      '${AppConstants.firstTimeUserKey}_config_$userId';

  Future<void> _resolvePreAuthFlow() async {
    if (_isResolvingPreAuthFlow || _preAuthFlowResolved) {
      return;
    }

    setState(() {
      _isResolvingPreAuthFlow = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final shouldShowWelcome =
        prefs.getBool(AppConstants.firstTimeUserKey) ?? true;

    if (!mounted) return;
    setState(() {
      _showPreAuthWelcome = shouldShowWelcome;
      _isShowingRegister = false;
      _preAuthFlowResolved = true;
      _isResolvingPreAuthFlow = false;
    });
  }

  Future<void> _dismissPreAuthWelcome({required bool openRegister}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.firstTimeUserKey, false);

    if (!mounted) return;
    setState(() {
      _showPreAuthWelcome = false;
      _isShowingRegister = openRegister;
    });
  }

  /// Called when "Get Started" is tapped — show pre-auth questions first.
  void _startPreAuthQuestions() {
    setState(() {
      _showPreAuthWelcome = false;
      _showPreAuthQuestions = true;
    });
  }

  /// Called when pre-auth questions are completed.
  Future<void> _onPreAuthQuestionsComplete(PreAuthAnswers answers) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(AppConstants.firstTimeUserKey, false);
    await prefs.setString(_preAuthAnswersKey, jsonEncode(answers.toJson()));

    if (!mounted) return;
    setState(() {
      _pendingPreAuthAnswers = answers;
      _showPreAuthQuestions = false;
      _isShowingRegister = true;
      _preAuthFlowResolved = true;
    });
  }

  Future<void> _resolvePostAuthFlow(AuthProvider authProvider) async {
    final currentUser = authProvider.currentUser;
    final userId = currentUser?.id;
    if (userId == null ||
        _isResolvingFlow ||
        _flowResolvedForUserId == userId) {
      return;
    }

    setState(() {
      _isResolvingFlow = true;
    });

    final prefs = await SharedPreferences.getInstance();
    final localCompleted =
        prefs.getBool(_onboardingCompletedKey(userId)) ?? false;
    var isCompleted = currentUser?.isOnboardingCompleted ?? false;

    // Backward compatibility: sync old local completion state to backend once.
    if (!isCompleted && localCompleted) {
      await authProvider.submitOnboarding({
        'level': currentUser?.cefrLevel ?? 'A1',
      });
      isCompleted = true;
    }

    if (!mounted) return;
    setState(() {
      _showOnboarding = !isCompleted;
      _flowResolvedForUserId = userId;
      _isResolvingFlow = false;
    });
  }

  Future<void> _completeOnboarding(
    AuthProvider authProvider,
    OnboardingAnswers answers,
  ) async {
    final userId = authProvider.currentUser?.id;
    if (userId == null) return;

    // Load any pre-auth answers collected before registration.
    PreAuthAnswers? preAuth = _pendingPreAuthAnswers;
    if (preAuth == null) {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_preAuthAnswersKey);
      if (raw != null) {
        try {
          preAuth = PreAuthAnswers.fromJson(
            jsonDecode(raw) as Map<String, dynamic>,
          );
        } catch (_) {}
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final config = <String, dynamic>{
      'goal': answers.goal,
      'level': answers.level,
      'interest': answers.interest,
      'theme_color': _themeColorForGoal(answers.goal),
      'current_plan_id': _planIdForAnswers(answers),
      'feature_flags': {
        'show_advanced_grammar_tab':
            answers.level != 'A1' && answers.level != 'A2',
        'show_business_lessons':
            answers.goal == 'business' || answers.interest == 'career',
      },
    };

    await prefs.setBool(_onboardingCompletedKey(userId), true);
    await prefs.setString(_onboardingConfigKey(userId), jsonEncode(config));
    await prefs.remove(_preAuthAnswersKey);

    await authProvider.submitOnboarding(
      answers.toJson(),
      displayName: (preAuth?.name.isNotEmpty ?? false) ? preAuth!.name : null,
      nativeLanguage: preAuth?.nativeLanguage,
    );

    // Refresh authoritative CEFR + numeric level snapshot immediately.
    if (mounted) {
      try {
        await context.read<LevelProvider>().fetchLevelFull();
      } catch (_) {
        // Keep onboarding non-blocking if level refresh fails.
      }
    }

    if (!mounted) return;
    setState(() {
      _showOnboarding = false;
    });
    authProvider.clearJustLoggedIn();
  }

  String _themeColorForGoal(String goal) {
    switch (goal) {
      case 'business':
        return '#0EA5E9';
      case 'exam':
        return '#F59E0B';
      case 'travel':
        return '#14B8A6';
      default:
        return '#30E8E8';
    }
  }

  String _planIdForAnswers(OnboardingAnswers answers) {
    return '${answers.goal}_${answers.level}_${answers.interest}'.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);

    // Show loading while checking auth state
    if (authProvider.isCheckingAuth) {
      return Scaffold(body: LoadingScreen(message: 'common.loading'.tr()));
    }

    // Detect when user just logged in
    if (authProvider.isAuthenticated && !_wasAuthenticated) {
      _wasAuthenticated = true;
      _flowResolvedForUserId = null;
      _showOnboarding = false;
      final userId = authProvider.currentUser?.id;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Load user settings when authenticated
        if (userId != null) {
          context.read<SettingsProvider>().loadSettings(userId, context);
        }
        _resolvePostAuthFlow(authProvider);
      });
    }

    // Reset state when user logs out
    if (!authProvider.isAuthenticated && _wasAuthenticated) {
      _wasAuthenticated = false;
      _showOnboarding = false;
      _flowResolvedForUserId = null;
      _preAuthFlowResolved = false;
      _showPreAuthWelcome = false;
      _showPreAuthQuestions = false;
      _isShowingRegister = false;
    }

    if (authProvider.isAuthenticated && !_isResolvingFlow) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolvePostAuthFlow(authProvider);
      });
    }

    if (!authProvider.isAuthenticated &&
        !_isResolvingPreAuthFlow &&
        !_preAuthFlowResolved) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _resolvePreAuthFlow();
      });
    }

    // Determine which page to show
    Widget currentPage;
    if (authProvider.isAuthenticated) {
      if (_isResolvingFlow) {
        currentPage = Scaffold(
          body: LoadingScreen(message: 'common.loading'.tr()),
        );
      } else if (_showOnboarding) {
        currentPage = OnboardingPage(
          onComplete: (answers) => _completeOnboarding(authProvider, answers),
        );
      } else {
        currentPage = const LearnerTheme(child: MainScreen());
      }
    } else {
      if (_isResolvingPreAuthFlow || !_preAuthFlowResolved) {
        currentPage = Scaffold(
          body: LoadingScreen(message: 'common.loading'.tr()),
        );
      } else if (_showPreAuthWelcome) {
        currentPage = WelcomePage(
          onGetStarted: _startPreAuthQuestions,
          onSkip: () => _dismissPreAuthWelcome(openRegister: false),
        );
      } else if (_showPreAuthQuestions) {
        currentPage = PreAuthQuestionsPage(
          onComplete: _onPreAuthQuestionsComplete,
          onBack: () => setState(() {
            _showPreAuthQuestions = false;
            _showPreAuthWelcome = true;
          }),
          onLogin: () => setState(() {
            _showPreAuthQuestions = false;
            _isShowingRegister = false;
            _preAuthFlowResolved = true;
          }),
        );
      } else {
        currentPage = _isShowingRegister
            ? const RegisterPage()
            : const LoginPage();
      }
    }

    // Use AnimatedSwitcher for smooth transitions between pages
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 600),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (Widget child, Animation<double> animation) {
        // Fade + Scale + Slide transition
        final fadeAnimation = Tween<double>(
          begin: 0.0,
          end: 1.0,
        ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOut));

        final scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        );

        final slideAnimation =
            Tween<Offset>(
              begin: const Offset(0.0, 0.05),
              end: Offset.zero,
            ).animate(
              CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
            );

        return FadeTransition(
          opacity: fadeAnimation,
          child: ScaleTransition(
            scale: scaleAnimation,
            child: SlideTransition(position: slideAnimation, child: child),
          ),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<String>(
          authProvider.isAuthenticated
              ? (_showOnboarding ? 'onboarding' : 'main')
              : (_showPreAuthWelcome
                    ? 'welcome'
                    : (_isShowingRegister ? 'register' : 'login')),
        ),
        child: currentPage,
      ),
    );
  }
}
