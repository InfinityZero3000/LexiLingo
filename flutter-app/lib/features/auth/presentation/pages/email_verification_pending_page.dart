import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class EmailVerificationPendingPage extends StatefulWidget {
  const EmailVerificationPendingPage({super.key, required this.email});

  final String email;

  @override
  State<EmailVerificationPendingPage> createState() =>
      _EmailVerificationPendingPageState();
}

class _EmailVerificationPendingPageState
    extends State<EmailVerificationPendingPage> {
  bool _resendLoading = false;
  String? _message;
  bool _isError = false;

  Future<void> _resend() async {
    setState(() {
      _resendLoading = true;
      _message = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.resendVerificationEmail(widget.email);

    if (!mounted) return;
    setState(() {
      _resendLoading = false;
      _isError = !success;
      _message = success
          ? 'auth.emailVerificationResendSuccess'.tr()
          : (authProvider.errorMessage ??
                'auth.emailVerificationResendError'.tr());
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.accentMintDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('auth.emailVerificationTitle'.tr()),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.xxl,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 72,
                    color: isDark
                        ? AppColors.accentMint
                        : Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'auth.emailVerificationTitle'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? AppColors.onGradient
                          : AppColors.surfaceDarkInput,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'auth.emailVerificationMessage'.tr(
                      namedArgs: {'email': widget.email},
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark
                          ? Colors.white70
                          : Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxl),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isError
                              ? Theme.of(context).colorScheme.error
                              : context.status.success,
                        ),
                      ),
                    ),
                  FilledButton(
                    onPressed: _resendLoading ? null : _resend,
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.accentMint,
                      foregroundColor: const Color(0xFF0B132B),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.mdAll,
                      ),
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: _resendLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'auth.emailVerificationResend'.tr(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  TextButton(
                    onPressed: () {
                      Navigator.of(context).pushAndRemoveUntil(
                        MaterialPageRoute(builder: (_) => const LoginPage()),
                        (route) => false,
                      );
                    },
                    child: Text(
                      'auth.emailVerificationBackToLogin'.tr(),
                      style: TextStyle(
                        color: isDark
                            ? AppColors.accentMint
                            : Theme.of(context).colorScheme.primary,
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
}
