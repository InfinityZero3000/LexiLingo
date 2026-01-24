import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class NotificationsPage extends StatelessWidget {
  const NotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        centerTitle: false,
        actions: [
          TextButton(
            onPressed: () {},
            child: const Text('Mark all as read', style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionHeader(context, 'Today'),
            _buildNotificationItem(
              context,
              icon: Icons.schedule,
              iconColor: AppColors.primary,
              title: "Time for your AI Chat!",
              subtitle: "Your daily 5-minute conversation practice is ready.",
              time: "2m ago",
              isUnread: true,
            ),
            _buildNotificationItem(
              context,
              icon: Icons.local_fire_department,
              iconColor: Colors.orange,
              title: "7-Day Streak!",
              subtitle: "You're on fire! Keep up the great work in vocabulary.",
              time: "1h ago",
              isUnread: true,
            ),
            
            _buildSectionHeader(context, 'Yesterday'),
            _buildNotificationItem(
              context,
              icon: Icons.update,
              iconColor: AppColors.textGrey,
              bgIconColor: Colors.grey.withOpacity(0.1),
              title: "New Lesson Available",
              subtitle: "Check out the new Business English module for advanced learners.",
              time: "23h ago",
            ),
            _buildNotificationItem(
              context,
              icon: Icons.emoji_events,
              iconColor: Colors.amber[700]!,
              bgIconColor: Colors.amber.withOpacity(0.1),
              title: "New Badge Earned!",
              subtitle: "You've unlocked the \"Word Master\" achievement.",
              time: "Yesterday",
            ),

            _buildSectionHeader(context, 'Earlier'),
            Opacity(
              opacity: 0.8,
              child: _buildNotificationItem(
                context,
                icon: Icons.menu_book,
                iconColor: AppColors.textGrey,
                bgIconColor: Colors.grey.withOpacity(0.1),
                title: "Weekly Summary Ready",
                subtitle: "See how many new words you mastered this week.",
                time: "3 days ago",
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 24, bottom: 8),
      child: Text(title,
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(fontWeight: FontWeight.bold, fontSize: 18)),
    );
  }

  Widget _buildNotificationItem(BuildContext context,
      {required IconData icon,
      required Color iconColor,
      Color? bgIconColor,
      required String title,
      required String subtitle,
      required String time,
      bool isUnread = false}) {
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.05))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isUnread)
             Container(
               margin: const EdgeInsets.only(top: 24, right: 8),
               width: 6, height: 6, decoration: const BoxDecoration(color: AppColors.primary, shape: BoxShape.circle)
             )
          else 
             const SizedBox(width: 14), // Spacer for alignment
          
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: bgIconColor ?? iconColor.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: AppColors.textGrey, height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(time, style: Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11, color: AppColors.textGrey)),
          ),
        ],
      ),
    );
  }
}
