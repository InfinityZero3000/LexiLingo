import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';
import '../providers/auth_provider.dart';

/// Keeps the inbox's "verify your email" entry in step with the account.
///
/// Draws nothing. Mounted on Home, which stays alive for the whole session.
/// It used to be a banner pinned to the top of Home; the request now waits in
/// the inbox, and Edit Profile holds the resend button.
class EmailVerificationSync extends StatefulWidget {
  const EmailVerificationSync({super.key});

  @override
  State<EmailVerificationSync> createState() => _EmailVerificationSyncState();
}

class _EmailVerificationSyncState extends State<EmailVerificationSync> {
  late final AppLifecycleListener _lifecycle;
  ({String? id, String? email, bool verified})? _synced;

  @override
  void initState() {
    super.initState();
    // The link is opened in the mail app or a browser; coming back is the
    // moment the status may have changed, so ask the server then.
    _lifecycle = AppLifecycleListener(onResume: _refreshIfUnverified);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  void _refreshIfUnverified() {
    final auth = context.read<AuthProvider>();
    final user = auth.currentUser;
    if (user != null && !user.isVerified) auth.refreshCurrentUser();
  }

  @override
  Widget build(BuildContext context) {
    final state = context
        .select<AuthProvider, ({String? id, String? email, bool verified})>(
          (auth) => (
            id: auth.currentUser?.id,
            email: auth.currentUser?.email,
            verified: auth.currentUser?.isVerified ?? true,
          ),
        );
    if (state.id != null && state != _synced) {
      _synced = state;
      final notifications = context.read<NotificationProvider>();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        notifications.syncEmailVerification(
          email: state.email,
          verified: state.verified,
        );
      });
    }
    return const SizedBox.shrink();
  }
}
