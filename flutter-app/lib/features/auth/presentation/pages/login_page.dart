import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lexilingo_app/core/widgets/language_switcher_button.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../providers/auth_provider.dart';
import 'email_verification_pending_page.dart';
import 'forgot_password_page.dart';
import 'register_page.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  static const int _maxFailedAttempts = 5;
  static const String _rememberPasswordKey = 'remember_password';
  static const String _savedEmailKey = 'saved_email';
  static const String _savedPasswordKey = 'saved_password';

  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _rememberPassword = false;
  int _failedAttempts = 0;

  bool get _isLockedAfterFailures => _failedAttempts >= _maxFailedAttempts;

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  bool _isInvalidCredentialMessage(String? message) {
    if (message == null) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('incorrect email or password') ||
        normalized.contains('invalid email or password') ||
        normalized.contains('auth_invalid');
  }

  bool _isEmailNotVerifiedMessage(String? message) {
    if (message == null) return false;
    final normalized = message.toLowerCase();
    return normalized.contains('not verified') ||
        normalized.contains('chưa được xác thực') ||
        normalized.contains('chưa xác thực');
  }

  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final remember = prefs.getBool(_rememberPasswordKey) ?? false;
    if (!remember) return;

    final savedEmail = prefs.getString(_savedEmailKey) ?? '';
    final savedPassword =
        await _secureStorage.read(key: _savedPasswordKey) ?? '';

    if (!mounted) return;
    setState(() {
      _rememberPassword = true;
      _emailController.text = savedEmail;
      _passwordController.text = savedPassword;
    });
  }

  Future<void> _persistCredentialPreference() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_rememberPasswordKey, _rememberPassword);

    if (_rememberPassword) {
      await Future.wait([
        prefs.setString(_savedEmailKey, _emailController.text.trim()),
        _secureStorage.write(
          key: _savedPasswordKey,
          value: _passwordController.text,
        ),
      ]);
      return;
    }

    await Future.wait([
      prefs.remove(_savedEmailKey),
      _secureStorage.delete(key: _savedPasswordKey),
    ]);
  }

  Future<void> _openForgotPassword() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ForgotPasswordPage(
          initialEmail: _emailController.text.trim().isEmpty
              ? null
              : _emailController.text.trim(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final canPop = Navigator.of(context).canPop();
    // Subscribe this route to locale changes so String.tr() labels refresh immediately.
    final localeCode = context.locale.languageCode;
    // Fit-to-screen scale: every `gap(full, compact)` call below smoothly
    // interpolates between its two values based on the *actual* usable
    // height (screen height minus safe-area insets minus the on-screen
    // keyboard, when open). This replaces a hard isCompact cutoff that only
    // looked at static screen height and never reacted to the keyboard —
    // which is exactly why the Google/Facebook buttons could end up pushed
    // below the fold while typing on shorter phones. Below `_tightHeight`
    // everything uses the tightest (compact) spacing already tuned to keep
    // the social-login row on screen; above `_roomyHeight` everything uses
    // full spacing; in between it scales continuously so it looks right on
    // every device size, not just two presets.
    const roomyHeight = 900.0;
    const tightHeight = 760.0;
    final mediaQuery = MediaQuery.of(context);
    final usableHeight =
        mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        mediaQuery.viewInsets.bottom;
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final fitT = ((usableHeight - tightHeight) / (roomyHeight - tightHeight))
        .clamp(0.0, 1.0);
    double gap(double full, double compact) =>
        compact + (full - compact) * fitT;
    final logoHeight = gap(40, 32);
    final heroHeight = isKeyboardOpen ? 0.0 : gap(320, 185);

    return Scaffold(
      key: ValueKey<String>('login-page-$localeCode'),
      backgroundColor: isDark
          ? AppColors.accentMintDark
          : AppColors.backgroundLight,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: 16,
                vertical: gap(8, 4),
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top app bar
                    Row(
                      children: [
                        canPop
                            ? AppBackButton(
                                onPressed: () => Navigator.of(context).pop(),
                                icon: Icons.arrow_back,
                                color: isDark
                                    ? Colors.white
                                    : AppColors.surfaceDarkInput,
                              )
                            : const SizedBox(width: 48),
                        Expanded(
                          child: Center(
                            child: Image.asset(
                              'assets/out-app/lexilingo-logo.png',
                              height: logoHeight,
                              fit: BoxFit.contain,
                              color: isDark ? Colors.white : null,
                            ),
                          ),
                        ),
                        const LanguageSwitcherButton(),
                      ],
                    ),

                    if (heroHeight > 0) ...[
                      SizedBox(height: gap(8, 4)),

                      // Hero
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          height: heroHeight,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0x3330E8E8), Color(0x2230E8E8)],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Image.network(
                            'https://lh3.googleusercontent.com/aida-public/AB6AXuC9e5sG5ITzGQOOtLmmixgmi3eqy1u2vjREx5V2LGBCdNg_bgu7OQarns0X8kgNuuuRN6bV1yWvZej9RBzXmsN0DYptA_CsuDNIuGLUOa_JlGU5R_fFBaQJZgQnWOvW6YVqMVd3tVGfLxAGrmQuwwyVsPQdEpGwB3E_bGE4Zbdw5Eya67psT55Ru81ggipsdLz1q7mHhNths64jCip1sXDvPCi_RBDeHWeza1RJmiuGVC9FfcWdVPLMLPZd2XM9pzu5ezA_FzA2O5g',
                            fit: BoxFit.cover,
                            errorBuilder: (context, _, __) => const Center(
                              child: Icon(Icons.language, size: 64),
                            ),
                          ),
                        ),
                      ),
                    ],

                    SizedBox(height: gap(24, 10)),
                    Text(
                      'auth.welcomeBack'.tr(),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark
                            ? Colors.white
                            : AppColors.surfaceDarkInput,
                      ),
                    ),
                    SizedBox(height: gap(24, 12)),

                    Text(
                      'auth.email'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: isDark
                            ? Colors.white
                            : AppColors.surfaceDarkInput,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      onChanged: (_) {
                        if (authProvider.errorMessage != null) {
                          authProvider.clearError();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'auth.emailHint'.tr(),
                        prefixIcon: Icon(
                          Icons.email_outlined,
                          color: isDark ? Colors.white70 : AppColors.textSlate,
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.surfaceDarkInput
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseEnterEmail'.tr();
                        }
                        if (!RegExp(
                          r'^[^@\s]+@[^@\s]+\.[^@\s]+$',
                        ).hasMatch(value.trim())) {
                          return 'auth.invalidEmail'.tr();
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: gap(16, 10)),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'auth.password'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.white
                                  : AppColors.surfaceDarkInput,
                            ),
                          ),
                        ),
                        TextButton(
                          onPressed: _openForgotPassword,
                          child: Text('auth.forgotPassword'.tr()),
                        ),
                      ],
                    ),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      onChanged: (_) {
                        if (authProvider.errorMessage != null) {
                          authProvider.clearError();
                        }
                      },
                      decoration: InputDecoration(
                        hintText: 'auth.enterYourPassword'.tr(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                        ),
                        filled: true,
                        fillColor: isDark
                            ? AppColors.surfaceDarkInput
                            : Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseEnterYourPassword'.tr();
                        }
                        return null;
                      },
                    ),

                    SizedBox(height: gap(8, 4)),
                    Row(
                      children: [
                        Checkbox(
                          value: _rememberPassword,
                          onChanged: (value) {
                            setState(() {
                              _rememberPassword = value ?? false;
                            });
                          },
                        ),
                        Expanded(
                          child: Text(
                            'auth.rememberPassword'.tr(),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: isDark
                                  ? Colors.white70
                                  : AppColors.surfaceDarkInput,
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: gap(20, 10)),
                    SizedBox(
                      height: gap(56, 48),
                      child: ElevatedButton(
                        onPressed:
                            authProvider.isLoading || _isLockedAfterFailures
                            ? null
                            : () async {
                                if (_formKey.currentState!.validate()) {
                                  final messenger = ScaffoldMessenger.of(
                                    context,
                                  );
                                  final navigator = Navigator.of(context);
                                  await authProvider.signInWithEmailPassword(
                                    _emailController.text.trim(),
                                    _passwordController.text,
                                  );

                                  if (!mounted) return;

                                  if (authProvider.isAuthenticated) {
                                    await _persistCredentialPreference();
                                    setState(() => _failedAttempts = 0);
                                  } else if (_isEmailNotVerifiedMessage(
                                    authProvider.errorMessage,
                                  )) {
                                    if (!mounted) return;
                                    final email = _emailController.text.trim();
                                    navigator.push(
                                      MaterialPageRoute(
                                        builder: (_) =>
                                            EmailVerificationPendingPage(
                                              email: email,
                                            ),
                                      ),
                                    );
                                  } else if (_isInvalidCredentialMessage(
                                    authProvider.errorMessage,
                                  )) {
                                    setState(() => _failedAttempts += 1);

                                    if (_isLockedAfterFailures) {
                                      messenger.showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'auth.wrongPasswordFiveTimes'.tr(),
                                          ),
                                        ),
                                      );
                                      await _openForgotPassword();
                                    }
                                  }
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: AppColors.accentMintDark,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 0,
                        ),
                        child: authProvider.isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: LottieLoadingWidget.tiny(),
                              )
                            : Text(
                                'auth.signIn'.tr(),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                      ),
                    ),

                    if (!_isLockedAfterFailures && _failedAttempts > 0) ...[
                      const SizedBox(height: 12),
                      Text(
                        'auth.wrongCredentialsAttempts'.tr(
                          namedArgs: {
                            'count': '$_failedAttempts',
                            'max': '$_maxFailedAttempts',
                          },
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.orange.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'auth.googleAccountHint'.tr(),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark
                              ? Colors.white70
                              : AppColors.textSlateLight,
                        ),
                      ),
                    ],

                    if (_isLockedAfterFailures) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.orange.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock_outline,
                              color: Colors.orange.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'auth.loginTemporarilyDisabled'.tr(),
                                style: TextStyle(color: Colors.orange.shade800),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    SizedBox(height: gap(24, 12)),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.surfaceDarkMuted
                                : AppColors.slate200,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'auth.orLoginWith'.tr(),
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: isDark
                                  ? AppColors.textMuted
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.surfaceDarkMuted
                                : AppColors.slate200,
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: gap(16, 10)),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: gap(56, 44),
                            child: OutlinedButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () async {
                                      await authProvider.signInWithGoogle();
                                    },
                              icon: const Icon(Icons.g_mobiledata, size: 26),
                              label: const Text('Google'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: gap(56, 44),
                            child: OutlinedButton.icon(
                              onPressed: authProvider.isLoading
                                  ? null
                                  : () async {
                                      await authProvider.signInWithFacebook();
                                    },
                              icon: const Icon(Icons.facebook, size: 22),
                              label: const Text('Facebook'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    SizedBox(height: gap(24, 12)),
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'auth.dontHaveAccount'.tr(),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDark
                                ? Colors.white70
                                : AppColors.textSlate,
                          ),
                        ),
                        TextButton(
                          onPressed: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const RegisterPage(),
                              ),
                            );
                          },
                          child: Text(
                            'auth.signUpForFree'.tr(),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ),

                    if (authProvider.errorMessage != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Colors.red.shade700,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                authProvider.errorMessage!,
                                style: TextStyle(color: Colors.red.shade700),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    SizedBox(height: gap(16, 8)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
