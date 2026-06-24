import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/home/presentation/widgets/home_ui_components.dart';
import 'package:lexilingo_app/features/level/level.dart';
import 'package:lexilingo_app/features/notifications/presentation/pages/notifications_page.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/notification_provider.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final authProvider = Provider.of<AuthProvider>(context);
    // Get user display name from AuthProvider
    final user = authProvider.currentUser;
    final displayName = user?.displayName.isNotEmpty == true
        ? user!.displayName
        : user?.username ?? 'profile.guestUser'.tr();

    return Consumer2<NotificationProvider, LevelProvider>(
      builder: (context, notificationProvider, levelProvider, child) {
        final totalXP = levelProvider.levelStatus.totalXP;
        return PersonalizedGreetingHeader(
          userName: displayName,
          totalXP: totalXP,
          avatarUrl: user?.avatarUrl,
          notificationCount: notificationProvider.unreadCount,
          onNotificationTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NotificationsPage()),
            );
          },
          onAvatarTap: () {
            // Navigate to profile or settings
          },
        );
      },
    );
  }
}
