import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'home_page.dart';
import '../../../course/presentation/screens/course_list_screen.dart';
import '../../../chat/presentation/pages/chat_page.dart';
import '../../../notifications/presentation/pages/notifications_page.dart';
import '../../../notifications/presentation/providers/notification_provider.dart';
import '../../../profile/presentation/pages/profile_page.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePageNew(),
    const CourseListScreen(),
    const ChatPage(),
    const NotificationsPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Consumer<NotificationProvider>(
        builder: (context, notificationProvider, child) {
          final unreadCount = notificationProvider.unreadCount;
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C2A38) : Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              boxShadow: [
                BoxShadow(
                  color: isDark
                      ? Colors.black.withValues(alpha: 0.4)
                      : Colors.black.withValues(alpha: 0.08),
                  blurRadius: 20,
                  spreadRadius: 0,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(24),
                topRight: Radius.circular(24),
              ),
              child: BottomNavigationBar(
              currentIndex: _currentIndex,
              onTap: (index) {
                setState(() {
                  _currentIndex = index;
                });
              },
              items: [
                const BottomNavigationBarItem(
                  icon: Icon(Icons.explore_outlined),
                  activeIcon: Icon(Icons.explore),
                  label: 'Discovery',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.menu_book_outlined),
                  activeIcon: Icon(Icons.menu_book),
                  label: 'Learning',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.chat_bubble_outline),
                  activeIcon: Icon(Icons.chat_bubble),
                  label: 'Chat',
                ),
                BottomNavigationBarItem(
                  icon: _buildNotificationIcon(
                    Icons.notifications_outlined,
                    unreadCount,
                    context,
                  ),
                  activeIcon: _buildNotificationIcon(
                    Icons.notifications,
                    unreadCount,
                    context,
                  ),
                  label: 'Notification',
                ),
                const BottomNavigationBarItem(
                  icon: Icon(Icons.account_circle_outlined),
                  activeIcon: Icon(Icons.account_circle),
                  label: 'Account',
                ),
              ],
            ),
          ),
        );
        },
      ),
    );
  }

  Widget _buildNotificationIcon(
    IconData icon,
    int unreadCount,
    BuildContext context,
  ) {
    if (unreadCount <= 0) {
      return Icon(icon);
    }
    return Badge(
      label: Text(
        unreadCount > 99 ? '99+' : '$unreadCount',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
      backgroundColor: Colors.red,
      child: Icon(icon),
    );
  }
}
