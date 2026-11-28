import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:provider/provider.dart';
import '../../../shared/admin_exit_scope.dart';
import 'auth_provider.dart';

/// Shown for a moment while the account is checked.
class AdminSplashScreen extends StatelessWidget {
  const AdminSplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

/// The signed-in account has no admin role.
class AdminNoAccessScreen extends StatelessWidget {
  const AdminNoAccessScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final needsGoogle =
        context.watch<AuthProvider>().user?.needsGoogleSignIn ?? false;
    return _GateMessage(
      icon: Icons.lock_outline_rounded,
      title: needsGoogle
          ? 'admin.gate.googleTitle'.tr()
          : 'admin.gate.noAccessTitle'.tr(),
      body: needsGoogle
          ? 'admin.gate.googleBody'.tr()
          : 'admin.gate.noAccessBody'.tr(),
    );
  }
}

/// The account could not be checked; offers a retry.
class AdminLoadErrorScreen extends StatelessWidget {
  const AdminLoadErrorScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    return _GateMessage(
      icon: Icons.cloud_off_rounded,
      title: 'admin.gate.loadErrorTitle'.tr(),
      body: auth.errorText?.resolve() ?? 'admin.gate.loadErrorBody'.tr(),
      onRetry: auth.retry,
    );
  }
}

class _GateMessage extends StatelessWidget {
  const _GateMessage({
    required this.icon,
    required this.title,
    required this.body,
    this.onRetry,
  });

  final IconData icon;
  final String title;
  final String body;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 48, color: theme.colorScheme.primary),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    body,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (onRetry != null) ...[
                    FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(160, kMinTapTarget),
                      ),
                      child: Text('admin.gate.retry'.tr()),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                  TextButton(
                    onPressed: AdminExitScope.maybeOf(context)?.onExit,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(160, kMinTapTarget),
                    ),
                    child: Text('admin.gate.exit'.tr()),
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
