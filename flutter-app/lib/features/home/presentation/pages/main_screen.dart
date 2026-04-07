import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../chat/presentation/providers/story_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'home_page.dart';
import '../../../course/presentation/screens/course_list_screen.dart';
import '../../../chat/presentation/pages/story_selection_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/core/network/api_config.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _lexiWarmedUp = false;

  @override
  void initState() {
    super.initState();
    _triggerPreWarming();
  }

  void _triggerPreWarming() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final auth = context.read<AuthProvider>();
        final storyProvider = context.read<StoryProvider>();
        final userId = auth.user?.id ?? 'guest';

        storyProvider.preWarmRecents(userId);
      } catch (e) {
        debugPrint('Pre-warming skipped: $e');
      }
    });
  }

  final List<Widget> _pages = [
    const HomePageNew(),
    const CourseListScreen(),
    const LexiChatPage(),
    const StorySelectionPage(),
    const ProfilePage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(index: _currentIndex, children: _pages),
      bottomNavigationBar: Builder(
        builder: (context) {
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
                type: BottomNavigationBarType.fixed,
                onTap: (index) {
                  if (index == 2 && !_lexiWarmedUp) {
                    _lexiWarmedUp = true;
                    _warmupAiModels();
                  }
                  setState(() => _currentIndex = index);
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
                  BottomNavigationBarItem(
                    icon: ClipOval(
                      child: Image.asset(
                        'assets/avatar/avatar-ai-chat.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.smart_toy_outlined, size: 20),
                      ),
                    ),
                    activeIcon: ClipOval(
                      child: Image.asset(
                        'assets/avatar/avatar-ai-chat.png',
                        width: 24,
                        height: 24,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            const Icon(Icons.smart_toy, size: 20),
                      ),
                    ),
                    label: 'Lexi',
                  ),
                  const BottomNavigationBarItem(
                    icon: Icon(Icons.chat_bubble_outline),
                    activeIcon: Icon(Icons.chat_bubble),
                    label: 'Chat',
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

  void _warmupAiModels() async {
    try {
      final url = Uri.parse('${ApiConfig.aiServiceUrl}/warmup');
      await http.post(url);
    } catch (_) {
      // Ignore error
    }
  }
}
