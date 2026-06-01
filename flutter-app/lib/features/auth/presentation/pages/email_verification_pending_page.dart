import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../providers/auth_provider.dart';
import 'login_page.dart';

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
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.mark_email_unread_outlined,
                    size: 72,
                    color: isDark ? AppColors.accentMint : AppColors.primary,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'auth.emailVerificationTitle'.tr(),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white : AppColors.surfaceDarkInput,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'auth.emailVerificationMessage'.tr(
                      namedArgs: {'email': widget.email},
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: isDark ? Colors.white70 : AppColors.textSlateLight,
                    ),
                  ),
                  const SizedBox(height: 32),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: Text(
                        _message!,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: _isError ? Colors.red : Colors.green,
                        ),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: _resendLoading ? null : _resend,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.accentMint,
                      foregroundColor: const Color(0xFF0B132B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(28),
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
                  const SizedBox(height: 16),
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
                            : AppColors.primary,
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
