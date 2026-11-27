import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/confirm_dialog.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';

/// Signs in with Facebook and, when the email already uses another sign-in
/// method, offers to link them. The confirm tap is what lets the browser open
/// the Google popup.
Future<void> signInWithFacebookOrLink(
  BuildContext context,
  AuthProvider auth,
) async {
  await auth.signInWithFacebook();
  final email = auth.facebookLinkEmail;
  if (email == null || !context.mounted) return;

  final confirmed = await showConfirm(
    context,
    title: 'auth.fbLinkTitle'.tr(),
    message: 'auth.fbLinkMessage'.tr(namedArgs: {'email': email}),
    confirmLabel: 'auth.fbLinkConfirm'.tr(),
  );
  if (confirmed) {
    await auth.linkFacebookWithGoogle();
  } else {
    auth.dismissFacebookLink();
  }
}
