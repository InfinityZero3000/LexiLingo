import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'login_page.dart';
import 'email_verification_pending_page.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class RegisterPage extends StatefulWidget {
  const RegisterPage({super.key});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isConfirmPasswordVisible = false;
  bool _acceptedTerms = false;
  bool _showTermsError = false;

  @override
  void dispose() {
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String _deriveUsername(String fullName) {
    final normalized = fullName
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');

    // Append a short numeric suffix to avoid "Username already taken" collisions
    // when multiple users share the same display name.
    final suffix = (DateTime.now().millisecondsSinceEpoch % 10000)
        .toString()
        .padLeft(4, '0');

    if (normalized.isNotEmpty) {
      return '${normalized}_$suffix';
    }

    return 'learner_${DateTime.now().millisecondsSinceEpoch}';
  }

  InputDecoration _inputDecoration({
    required BuildContext context,
    required String hint,
    required IconData icon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0xFFD7DEE7)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: Color(0xFFD7DEE7)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(24),
        borderSide: const BorderSide(color: AppColors.accentMint, width: 1.6),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          onPressed: () {
                            if (Navigator.of(context).canPop()) {
                              Navigator.of(context).pop();
                              return;
                            }
                            Navigator.of(context).pushReplacement(
                              MaterialPageRoute(
                                builder: (_) => const LoginPage(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.arrow_back),
                        ),
                        Expanded(
                          child: Text(
                            'auth.createAccount'.tr(),
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: const Color(0xFF0B132B),
                            ),
                          ),
                        ),
                        const SizedBox(width: 48),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'auth.startJourney'.tr(),
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF0B132B),
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'auth.joinLearners'.tr(),
                      style: textTheme.titleMedium?.copyWith(
                        color: const Color(0xFF3E536B),
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 30),

                    Text(
                      'auth.fullName'.tr(),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _fullNameController,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        context: context,
                        hint: 'auth.enterYourName'.tr(),
                        icon: Icons.person_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'auth.pleaseEnterName'.tr();
                        }
                        if (value.trim().length < 2) {
                          return 'auth.nameMinLength'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),
                    Text(
                      'auth.email'.tr(),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        context: context,
                        hint: 'auth.emailHint'.tr(),
                        icon: Icons.mail_outline,
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
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

                    const SizedBox(height: 20),
                    Text(
                      'auth.password'.tr(),
                      style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: !_isPasswordVisible,
                      textInputAction: TextInputAction.next,
                      decoration: _inputDecoration(
                        context: context,
                        hint: 'auth.createPassword'.tr(),
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _isPasswordVisible = !_isPasswordVisible;
                            });
                          },
                          icon: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseEnterPassword'.tr();
                        }
                        if (value.length < 8) {
                          return 'auth.passwordMinLength'.tr();
                        }
                        if (!RegExp(r'[A-Z]').hasMatch(value)) {
                          return 'auth.passwordNeedsUppercase'.tr();
                        }
                        if (!RegExp(r'[a-z]').hasMatch(value)) {
                          return 'auth.passwordNeedsLowercase'.tr();
                        }
                        if (!RegExp(r'[0-9]').hasMatch(value)) {
                          return 'auth.passwordNeedsNumber'.tr();
                        }
                        if (!RegExp(
                          r'[!@#\$%^&*(),.?":{}|<>_\-+=\[\]\\/~`]',
                        ).hasMatch(value)) {
                          return 'auth.passwordNeedsSpecial'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 20),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: !_isConfirmPasswordVisible,
                      textInputAction: TextInputAction.done,
                      decoration: _inputDecoration(
                        context: context,
                        hint: 'auth.confirmYourPassword'.tr(),
                        icon: Icons.lock_outline,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _isConfirmPasswordVisible =
                                  !_isConfirmPasswordVisible;
                            });
                          },
                          icon: Icon(
                            _isConfirmPasswordVisible
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'auth.pleaseConfirmPassword'.tr();
                        }
                        if (value != _passwordController.text) {
                          return 'auth.passwordMismatch'.tr();
                        }
                        return null;
                      },
                    ),

                    const SizedBox(height: 16),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Checkbox(
                          value: _acceptedTerms,
                          onChanged: (value) {
                            setState(() {
                              _acceptedTerms = value ?? false;
                              if (_acceptedTerms) {
                                _showTermsError = false;
                              }
                            });
                          },
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(6),
                          ),
                          side: const BorderSide(color: Color(0xFFB8C7D9)),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: RichText(
                              text: TextSpan(
                                style: textTheme.bodyLarge?.copyWith(
                                  color: const Color(0xFF3E536B),
                                ),
                                children: [
                                  TextSpan(text: 'auth.termsPrefix'.tr()),
                                  TextSpan(
                                    text: 'auth.termsOfService'.tr(),
                                    style: const TextStyle(
                                      color: AppColors.accentMint,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(text: 'auth.termsAnd'.tr()),
                                  TextSpan(
                                    text: 'auth.privacyPolicy'.tr(),
                                    style: const TextStyle(
                                      color: AppColors.accentMint,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_showTermsError) ...[
                      const SizedBox(height: 4),
                      Text(
                        'auth.pleaseAcceptTerms'.tr(),
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: 16),
                    SizedBox(
                      height: 58,
                      child: ElevatedButton(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                final isValid =
                                    _formKey.currentState?.validate() ?? false;
                                if (!isValid) {
                                  return;
                                }

                                if (!_acceptedTerms) {
                                  setState(() {
                                    _showTermsError = true;
                                  });
                                  return;
                                }

                                final nav = Navigator.of(context);
                                await authProvider.register(
                                  email: _emailController.text.trim(),
                                  username: _deriveUsername(
                                    _fullNameController.text,
                                  ),
                                  password: _passwordController.text,
                                  displayName: _fullNameController.text.trim(),
                                );

                                // If registration succeeded, navigate to email verification page.
                                if (authProvider.errorMessage == null &&
                                    mounted) {
                                  nav.pushReplacement(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          EmailVerificationPendingPage(
                                            email: _emailController.text.trim(),
                                          ),
                                    ),
                                  );
                                }
                              },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: const Color(0xFF0B132B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
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
                                'auth.createAccount'.tr(),
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Row(
                      children: [
                        const Expanded(
                          child: Divider(color: Color(0xFFD7DEE7)),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(
                            'auth.orContinueWith'.tr(),
                            style: textTheme.labelLarge?.copyWith(
                              color: const Color(0xFF8C9AAF),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        const Expanded(
                          child: Divider(color: Color(0xFFD7DEE7)),
                        ),
                      ],
                    ),

                    const SizedBox(height: 18),
                    SizedBox(
                      height: 58,
                      child: OutlinedButton.icon(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                await authProvider.signInWithGoogle();
                              },
                        icon: const Icon(Icons.g_mobiledata, size: 30),
                        label: Text(
                          'auth.continueWithGoogle'.tr(),
                          style: const TextStyle(
                            color: Color(0xFF0B132B),
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: AppColors.surfaceLight,
                          side: const BorderSide(color: Color(0xFFD7DEE7)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    SizedBox(
                      height: 58,
                      child: ElevatedButton.icon(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                await authProvider.signInWithFacebook();
                              },
                        icon: Icon(
                          Icons.facebook,
                          color: AppColors.surfaceLight,
                        ),
                        label: Text(
                          'auth.continueWithFacebook'.tr(),
                          style: TextStyle(
                            color: AppColors.surfaceLight,
                            fontWeight: FontWeight.w700,
                            fontSize: 18,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF0B132B),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(28),
                          ),
                          elevation: 0,
                        ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Center(
                      child: Wrap(
                        children: [
                          Text(
                            'auth.alreadyHaveAccount'.tr(),
                            style: textTheme.titleMedium?.copyWith(
                              color: const Color(0xFF3E536B),
                            ),
                          ),
                          GestureDetector(
                            onTap: () {
                              if (Navigator.of(context).canPop()) {
                                Navigator.of(context).pop();
                                return;
                              }
                              Navigator.of(context).pushReplacement(
                                MaterialPageRoute(
                                  builder: (_) => const LoginPage(),
                                ),
                              );
                            },
                            child: Text(
                              'auth.login'.tr(),
                              style: textTheme.titleMedium?.copyWith(
                                color: AppColors.accentMint,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    if (authProvider.errorMessage != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3F3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFFFCFCF)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: AppColors.errorBright,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                authProvider.errorMessage!,
                                style: const TextStyle(
                                  color: AppColors.errorDark,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (kIsWeb) const SizedBox(height: 24),
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
