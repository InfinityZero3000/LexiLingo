import 'package:flutter/widgets.dart';
import 'package:lexilingo_app/core/utils/constants.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Shows the login page. Only AuthWrapper, the app's root, may build it: it is
/// what notices the sign-in and resets per-account state. A bare login page
/// pushed in its place left the learner signed in and still looking at the form.
Future<void> openLogin(NavigatorState navigator) async {
  final prefs = await SharedPreferences.getInstance();
  // Whoever asks to log in has been past the first-run welcome.
  await prefs.setBool(AppConstants.firstTimeUserKey, false);
  if (!navigator.mounted) return;
  navigator.pushNamedAndRemoveUntil('/', (_) => false);
}

/// A sign-in changes the root underneath, not the pages stacked on top of it.
void closeAuthPagesWhenSignedIn(
  NavigatorState navigator, {
  required bool signedIn,
}) {
  if (signedIn && navigator.mounted && navigator.canPop()) {
    navigator.popUntil((route) => route.isFirst);
  }
}
