import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import '../providers/notification_provider.dart';
import '../widgets/empty_notification_widget.dart';
import '../../domain/entities/notification_entity.dart';

/// Notifications Page
/// Displays all notifications grouped by date with real-time updates
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  @override
  void initState() {
    super.initState();
    // Load notifications when page is opened
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<NotificationProvider>().loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: false,
        actions: [
          Consumer<NotificationProvider>(
            builder: (context, provider, child) {
              if (!provider.hasUnread) return const SizedBox.shrink();
              return TextButton(
                onPressed: () => provider.markAllAsRead(),
                child: const Text(
                  'Mark all as read',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: Consumer<NotificationProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.notifications.isEmpty) {
            return _buildLoadingState();
          }

          if (provider.errorMessage != null && provider.notifications.isEmpty) {
            return _buildErrorState(context, provider);
          }

          if (!provider.hasNotifications) {
            return _buildEmptyState(context);
          }

          return RefreshIndicator(
            onRefresh: () => provider.refreshNotifications(),
            child: ListView.builder(
              padding: const EdgeInsets.only(bottom: 80),
              itemCount: provider.groupedNotifications.length,
              itemBuilder: (context, index) {
                final group = provider.groupedNotifications[index];
                return _buildNotificationGroup(context, group, provider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildLoadingState() {
    return const LoadingScreen(message: 'Loading notifications...');
  }

  Widget _buildErrorState(BuildContext context, NotificationProvider provider) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red[300],
            ),
            const SizedBox(height: 16),
            Text(
              'Something went wrong',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              provider.errorMessage ?? 'Failed to load notifications',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey[600],
                  ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => provider.loadNotifications(),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return EmptyNotificationWidget(
      title: 'No Notifications Yet',
      description: 'You\'ll see notifications about your learning progress, achievements, and reminders here.',
      buttonText: 'Refresh',
      onRefresh: () => context.read<NotificationProvider>().refreshNotifications(),
    );
  }

  Widget _buildNotificationGroup(
    BuildContext context,
    NotificationGroup group,
    NotificationProvider provider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader(context, group.title),
        ...group.notifications.asMap().entries.map(
          (entry) {
            final index = entry.key;
            final notification = entry.value;
            return AnimatedListItem(
              index: index,
              child: _buildNotificationItem(
                context,
                notification: notification,
                onTap: () => _handleNotificationTap(context, notification, provider),
                onDismiss: () => provider.deleteNotification(notification.id),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context, {
    required NotificationEntity notification,
    required VoidCallback onTap,
    required VoidCallback onDismiss,
  }) {
    final icon = _getIconData(notification.iconIdentifier);
    final iconColor = _getColor(notification.colorHex);

    return Dismissible(
      key: Key(notification.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismiss(),
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: notification.isRead
                ? Theme.of(context).cardColor
                : AppColors.primary.withValues(alpha: 0.03),
            border: Border(
              bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.05)),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!notification.isRead)
                Container(
                  margin: const EdgeInsets.only(top: 24, right: 8),
                  width: 6,
                  height: 6,
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                )
              else
                const SizedBox(width: 14),
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notification.title,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      notification.body,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: AppColors.textGrey,
                            height: 1.3,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  notification.relativeTimeString,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontSize: 11,
                        color: AppColors.textGrey,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _handleNotificationTap(
    BuildContext context,
    NotificationEntity notification,
    NotificationProvider provider,
  ) {
    // Mark as read
    if (!notification.isRead) {
      provider.markAsRead(notification.id);
    }

    // Navigate based on notification type
    switch (notification.type) {
      case NotificationType.streakReminder:
      case NotificationType.lessonReminder:
        // Could navigate to home or learning screen
        break;
      case NotificationType.achievement:
        // Could navigate to achievements screen
        break;
      case NotificationType.newContent:
        // Could navigate to courses screen
        break;
      default:
        // Just mark as read
        break;
    }
  }

  IconData _getIconData(String? identifier) {
    switch (identifier) {
      case 'local_fire_department':
        return Icons.local_fire_department;
      case 'schedule':
        return Icons.schedule;
      case 'emoji_events':
        return Icons.emoji_events;
      case 'new_releases':
        return Icons.new_releases;
      case 'menu_book':
        return Icons.menu_book;
      case 'people':
        return Icons.people;
      case 'info':
        return Icons.info;
      case 'update':
        return Icons.update;
      default:
        return Icons.notifications;
    }
  }

  Color _getColor(String? hexColor) {
    if (hexColor == null || hexColor.isEmpty) {
      return AppColors.primary;
    }

    try {
      final hex = hexColor.replaceFirst('#', '');
      return Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      return AppColors.primary;
    }
  }
}
