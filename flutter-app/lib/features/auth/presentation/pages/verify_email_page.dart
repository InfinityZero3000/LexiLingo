import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Opened from the link in the verification email. The first verification signs the learner
/// in and goes straight on to onboarding; a used or expired link offers a fresh one.
class VerifyEmailPage extends StatefulWidget {
  final String? token;

  /// Defaults to [AuthProvider.verifyEmailLink]; tests pass their own.
  final Future<VerifyEmailOutcome> Function(String token)? verify;

  const VerifyEmailPage({super.key, required this.token, this.verify});

  @override
  State<VerifyEmailPage> createState() => _VerifyEmailPageState();
}

class _VerifyEmailPageState extends State<VerifyEmailPage> {
  VerifyEmailOutcome? _outcome;
  final _emailController = TextEditingController();
  bool _resending = false;
  String? _resendMessage;
  bool _resendFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final token = widget.token;
    if (token == null || token.isEmpty) {
      setState(() => _outcome = VerifyEmailOutcome.failed);
      return;
    }
    final verify =
        widget.verify ?? context.read<AuthProvider>().verifyEmailLink;
    final outcome = await verify(token);
    if (!mounted) return;
    if (outcome == VerifyEmailOutcome.signedIn) {
      // The root route is AuthWrapper, which shows onboarding to a fresh account.
      Navigator.of(context).pushNamedAndRemoveUntil('/', (_) => false);
      return;
    }
    setState(() => _outcome = outcome);
  }

  Future<void> _resend() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) return;
    setState(() => _resending = true);
    final ok = await context.read<AuthProvider>().resendVerificationEmail(
      email,
    );
    if (!mounted) return;
    setState(() {
      _resending = false;
      _resendFailed = !ok;
      _resendMessage = ok
          ? 'auth.emailVerificationResendSuccess'.tr()
          : 'auth.emailVerificationResendError'.tr();
    });
  }

  void _toLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final outcome = _outcome;

    final (IconData icon, String title, String? body) = switch (outcome) {
      null => (
        Icons.mark_email_read_outlined,
        'auth.verifyEmailChecking'.tr(),
        null,
      ),
      VerifyEmailOutcome.signedIn || VerifyEmailOutcome.verified => (
        Icons.verified_outlined,
        'auth.verifyEmailDoneTitle'.tr(),
        'auth.verifyEmailDoneMessage'.tr(),
      ),
      VerifyEmailOutcome.failed => (
        Icons.link_off_rounded,
        'auth.verifyEmailFailedTitle'.tr(),
        'auth.verifyEmailFailedMessage'.tr(),
      ),
    };

    return Scaffold(
      appBar: AppBar(
        title: Text('auth.emailVerificationTitle'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xl,
                  vertical: AppSpacing.xxl,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(icon, size: 72, color: scheme.primary),
                    const SizedBox(height: AppSpacing.xl),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (body != null) ...[
                      const SizedBox(height: AppSpacing.md),
                      Text(
                        body,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.xxl),
                    if (outcome == null)
                      const Center(child: CircularProgressIndicator()),
                    if (outcome == VerifyEmailOutcome.verified)
                      FilledButton(
                        onPressed: _toLogin,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: const Color(0xFF0B132B),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: Text('auth.login'.tr()),
                      ),
                    if (outcome == VerifyEmailOutcome.failed) ...[
                      TextField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        decoration: InputDecoration(
                          labelText: 'auth.email'.tr(),
                          hintText: 'auth.emailHint'.tr(),
                        ),
                        onSubmitted: (_) => _resend(),
                      ),
                      const SizedBox(height: AppSpacing.lg),
                      if (_resendMessage != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.md),
                          child: Text(
                            _resendMessage!,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: _resendFailed
                                  ? scheme.error
                                  : scheme.primary,
                            ),
                          ),
                        ),
                      FilledButton(
                        onPressed: _resending ? null : _resend,
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.accentMint,
                          foregroundColor: const Color(0xFF0B132B),
                          minimumSize: const Size.fromHeight(48),
                        ),
                        child: _resending
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text('auth.emailVerificationResend'.tr()),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _toLogin,
                        child: Text('auth.emailVerificationBackToLogin'.tr()),
                      ),
                    ],
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
