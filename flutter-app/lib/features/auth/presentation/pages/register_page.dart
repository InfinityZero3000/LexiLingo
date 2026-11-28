import 'package:lexilingo_app/features/auth/presentation/auth_navigation.dart';
import 'package:lexilingo_app/core/widgets/tap_target.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'email_verification_pending_page.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/features/auth/presentation/widgets/facebook_sign_in.dart';

class RegisterPage extends StatefulWidget {
  /// The name the pre-sign-up questions already asked for.
  final String? initialName;

  /// Reports the name field when the learner signs up by any route, so the
  /// name they edited here is not overwritten by the starter answer later.
  final Future<void> Function(String name)? onNameChosen;

  const RegisterPage({super.key, this.initialName, this.onNameChosen});

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  late final _fullNameController = TextEditingController(
    text: widget.initialName,
  );
  final _emailController = TextEditingController();

  Future<void> _reportName() async =>
      widget.onNameChosen?.call(_fullNameController.text.trim());
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final outline = isDark
        ? AppColors.textOnDarkMuted
        : const Color(0xFFD7DEE7);
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.lg,
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: BorderSide(color: outline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: BorderSide(color: outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        borderSide: const BorderSide(color: AppColors.accentMint, width: 1.6),
      ),
    );
  }

  void _goToLogin() {
    if (!mounted) return;
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
      return;
    }
    openLogin(Navigator.of(context));
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    final theme = Theme.of(context);
    final textTheme = theme.textTheme;
    final isDark = theme.brightness == Brightness.dark;
    final strongText = AppColorRoles.textPrimary(isDark);
    final mutedText = isDark
        ? AppColors.textOnDarkMuted
        : const Color(0xFF3E536B);

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: AppSpacing.sm,
              ),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AppBackButton(
                          onPressed: _goToLogin,
                          icon: Icons.arrow_back,
                          color: strongText,
                        ),
                        Expanded(
                          child: Text(
                            'auth.createAccount'.tr(),
                            textAlign: TextAlign.center,
                            style: textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: strongText,
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
                        color: strongText,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'auth.joinLearners'.tr(),
                      style: textTheme.titleMedium?.copyWith(
                        color: mutedText,
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

                    const SizedBox(height: AppSpacing.lg),
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
                          side: BorderSide(
                            color: isDark
                                ? AppColors.textOnDarkMuted
                                : const Color(0xFFB8C7D9),
                          ),
                        ),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.md),
                            child: RichText(
                              text: TextSpan(
                                style: textTheme.bodyLarge?.copyWith(
                                  color: mutedText,
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
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        'auth.pleaseAcceptTerms'.tr(),
                        style: textTheme.bodyMedium?.copyWith(
                          color: Colors.red.shade700,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],

                    const SizedBox(height: AppSpacing.lg),
                    SizedBox(
                      height: 58,
                      child: FilledButton(
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
                                await _reportName();
                                await authProvider.register(
                                  email: _emailController.text.trim(),
                                  username: _deriveUsername(
                                    _fullNameController.text,
                                  ),
                                  password: _passwordController.text,
                                  displayName: _fullNameController.text.trim(),
                                );

                                if (authProvider.errorMessage == null &&
                                    mounted) {
                                  // Sign straight in: an unverified account may learn, and
                                  // Home keeps asking it to verify. An older backend still
                                  // refuses, which falls back to the inbox page.
                                  await authProvider.signInWithEmailPassword(
                                    _emailController.text.trim(),
                                    _passwordController.text,
                                  );
                                  if (!mounted) return;
                                  if (authProvider.isAuthenticated) {
                                    nav.pushNamedAndRemoveUntil(
                                      '/',
                                      (_) => false,
                                    );
                                    return;
                                  }
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
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: const Color(0xFF0B132B),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
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
                                style: Theme.of(context).textTheme.sectionTitle
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                      ),
                    ),

                    const SizedBox(height: 28),
                    Row(
                      children: [
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.textOnDarkMuted
                                : const Color(0xFFD7DEE7),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                          ),
                          child: Text(
                            'auth.orContinueWith'.tr(),
                            style: textTheme.labelLarge?.copyWith(
                              color: isDark
                                  ? AppColors.textOnDarkMuted
                                  : const Color(0xFF8C9AAF),
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        Expanded(
                          child: Divider(
                            color: isDark
                                ? AppColors.textOnDarkMuted
                                : const Color(0xFFD7DEE7),
                          ),
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
                                final nav = Navigator.of(context);
                                await _reportName();
                                await authProvider.signInWithGoogle();
                                closeAuthPagesWhenSignedIn(
                                  nav,
                                  signedIn: authProvider.isAuthenticated,
                                );
                              },
                        icon: const Icon(Icons.g_mobiledata, size: 30),
                        label: Text(
                          'auth.continueWithGoogle'.tr(),
                          style: Theme.of(context).textTheme.sectionTitle
                              ?.copyWith(
                                color: Color(0xFF0B132B),
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        style: OutlinedButton.styleFrom(
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.surface,
                          side: const BorderSide(color: Color(0xFFD7DEE7)),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      height: 58,
                      child: FilledButton.icon(
                        onPressed: authProvider.isLoading
                            ? null
                            : () async {
                                final nav = Navigator.of(context);
                                await _reportName();
                                if (!context.mounted) return;
                                await signInWithFacebookOrLink(
                                  context,
                                  authProvider,
                                  toPasswordForm: _goToLogin,
                                );
                                closeAuthPagesWhenSignedIn(
                                  nav,
                                  signedIn: authProvider.isAuthenticated,
                                );
                              },
                        icon: Icon(
                          Icons.facebook,
                          color: Theme.of(context).colorScheme.surface,
                        ),
                        label: Text(
                          'auth.continueWithFacebook'.tr(),
                          style: Theme.of(context).textTheme.sectionTitle
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.surface,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0B132B),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.mdAll,
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
                              color: mutedText,
                            ),
                          ),
                          TapTarget(
                            onTap: _goToLogin,
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
                      const SizedBox(height: AppSpacing.lg),
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.md),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF3F3),
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          border: Border.all(color: const Color(0xFFFFCFCF)),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: Theme.of(context).colorScheme.error,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: SelectableText(
                                authProvider.errorMessage!,
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.error,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (kIsWeb) const SizedBox(height: AppSpacing.xl),
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
