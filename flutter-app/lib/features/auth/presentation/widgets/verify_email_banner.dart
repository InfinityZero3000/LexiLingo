import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Shown on Home while the signed-in account has not verified its email. Unverified
/// accounts may learn; this keeps asking, and offers a fresh link.
class VerifyEmailBanner extends StatefulWidget {
  const VerifyEmailBanner({super.key});

  @override
  State<VerifyEmailBanner> createState() => _VerifyEmailBannerState();
}

class _VerifyEmailBannerState extends State<VerifyEmailBanner> {
  bool _sending = false;

  Future<void> _resend(String email) async {
    setState(() => _sending = true);
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await auth.resendVerificationEmail(email);
    if (!mounted) return;
    setState(() => _sending = false);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? 'auth.emailVerificationResendSuccess'.tr()
              : 'auth.emailVerificationResendError'.tr(),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = context.select<AuthProvider, ({String? email, bool verified})>(
      (auth) => (
        email: auth.currentUser?.email,
        verified: auth.currentUser?.isVerified ?? true,
      ),
    );
    final email = user.email;
    if (user.verified || email == null || email.isEmpty) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Material(
        color: scheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Icon(
                Icons.mark_email_unread_outlined,
                color: scheme.onTertiaryContainer,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'auth.verifyEmailBanner'.tr(),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onTertiaryContainer,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              TextButton(
                onPressed: _sending ? null : () => _resend(email),
                child: _sending
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('auth.verifyEmailBannerAction'.tr()),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
