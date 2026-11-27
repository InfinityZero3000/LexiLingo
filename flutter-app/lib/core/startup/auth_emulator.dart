import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// `host:port` of a local Firebase Auth emulator, for development only.
const _configured = String.fromEnvironment('FIREBASE_AUTH_EMULATOR');

/// The emulator to use, or null. Never in a release build, and only on this
/// machine: sign-ins against an emulator prove nothing about who someone is.
@visibleForTesting
(String, int)? authEmulatorTarget(String value, {required bool release}) {
  final parts = value.split(':');
  if (release || parts.length != 2) return null;
  final port = int.tryParse(parts[1]);
  const local = {'localhost', '127.0.0.1'};
  return port != null && local.contains(parts[0]) ? (parts[0], port) : null;
}

/// Offers unlimited fake Google and Facebook accounts, so the sign-in and
/// merge flows can be tested without real ones. See docs/operations/AUTH_TESTING.md.
Future<void> connectAuthEmulatorIfConfigured() async {
  final target = authEmulatorTarget(_configured, release: kReleaseMode);
  if (target == null) return;
  await FirebaseAuth.instance.useAuthEmulator(target.$1, target.$2);
}
