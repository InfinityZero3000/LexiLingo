import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

/// Signs in with Facebook. When the email already has an account, asks whether
/// to merge and walks through the proof. Every popup opens from a confirm tap,
/// which is what lets the browser allow it. [toPasswordForm] takes the learner
/// to where they can type their password, if this is not that page.
Future<void> signInWithFacebookOrLink(
  BuildContext context,
  AuthProvider auth, {
  VoidCallback? toPasswordForm,
}) async {
  await auth.signInWithFacebook();
  var step = auth.facebookMergeStep;
  while (step != FacebookMergeStep.none) {
    if (!context.mounted) {
      // A half-done proof holds a Firebase session; a waiting merge does not.
      if (step != FacebookMergeStep.signInToMerge) auth.dismissFacebookLink();
      return;
    }
    final carryOn = await _ask(context, auth, step, toPasswordForm);
    if (!carryOn) return;
    step = auth.facebookMergeStep;
  }
}

/// Shows one merge question; false when there is nothing left to ask.
Future<bool> _ask(
  BuildContext context,
  AuthProvider auth,
  FacebookMergeStep step,
  VoidCallback? toPasswordForm,
) async {
  final email = auth.facebookMergeEmail;
  final usesGoogle =
      step == FacebookMergeStep.signInToMerge && auth.facebookMergeAllowsGoogle;
  final offersPassword = usesGoogle && auth.facebookMergeAllowsPassword;

  final (title, message, confirm) = switch (step) {
    FacebookMergeStep.proveWithGoogle => (
      'auth.fbLinkTitle'.tr(),
      email == null
          ? 'auth.fbLinkMessageNoEmail'.tr()
          : 'auth.fbLinkMessage'.tr(namedArgs: {'email': email}),
      'auth.fbLinkConfirm'.tr(),
    ),
    FacebookMergeStep.confirmFacebook => (
      'auth.fbLinkFinishTitle'.tr(),
      'auth.fbLinkFinishMessage'.tr(),
      'auth.fbLinkFinishConfirm'.tr(),
    ),
    _ => (
      'auth.fbLinkTitle'.tr(),
      (usesGoogle
              ? (auth.facebookMergeAllowsPassword
                    ? 'auth.fbMergeGoogleOrPassword'
                    : 'auth.fbMergeGoogle')
              : 'auth.fbMergePassword')
          .tr(namedArgs: {'email': email ?? ''}),
      (usesGoogle ? 'auth.fbLinkConfirm' : 'auth.fbMergeContinue').tr(),
    ),
  };

  final confirmed = await showConfirm(
    context,
    title: title,
    message: message,
    confirmLabel: confirm,
    cancelLabel:
        (offersPassword ? 'auth.fbMergeUsePassword' : 'auth.fbMergeNotNow')
            .tr(),
  );
  if (!confirmed) {
    // With a password as the other way in, the merge waits for it; the hint on
    // the form is where it can be dropped.
    if (offersPassword) {
      toPasswordForm?.call();
    } else {
      auth.dismissFacebookLink();
    }
    return false;
  }

  switch (step) {
    case FacebookMergeStep.proveWithGoogle:
      await auth.linkFacebookWithGoogle();
    case FacebookMergeStep.confirmFacebook:
      await auth.finishFacebookLink();
    case FacebookMergeStep.signInToMerge:
      // With Google it happens now; with a password the learner types it into
      // the form, and the merge follows that sign-in.
      if (usesGoogle) {
        await auth.signInWithGoogle();
      } else if (context.mounted) {
        toPasswordForm?.call();
      }
      return false;
    case FacebookMergeStep.none:
      return false;
  }
  return true;
}

/// Says what to do while a merge waits for a sign-in. Guidance, not an error.
class FacebookMergeHint extends StatelessWidget {
  const FacebookMergeHint({super.key, required this.auth});

  final AuthProvider auth;

  @override
  Widget build(BuildContext context) {
    if (auth.facebookMergeStep != FacebookMergeStep.signInToMerge) {
      return const SizedBox.shrink();
    }
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        color: scheme.secondaryContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Icon(Icons.link_rounded, color: scheme.onSecondaryContainer),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  'auth.fbMergeHint'.tr(
                    namedArgs: {'email': auth.facebookMergeEmail ?? ''},
                  ),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'auth.fbMergeNotNow'.tr(),
                color: scheme.onSecondaryContainer,
                onPressed: auth.dismissFacebookLink,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
