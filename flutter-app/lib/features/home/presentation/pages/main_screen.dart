import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:provider/provider.dart';
import '../../../chat/presentation/providers/story_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'home_page.dart';
import '../../../course/presentation/screens/course_list_screen.dart';
import '../../../chat/presentation/pages/story_selection_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  bool _lexiWarmedUp = false;

  // Pages are built lazily — only when the tab is first visited.
  static const int _pageCount = 5;
  final Map<int, Widget> _pageCache = {};

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const HomePageNew();
      case 1:
        return const CourseListScreen();
      case 2:
        return const LexiChatPage();
      case 3:
        return const StorySelectionPage();
      case 4:
        return const ProfilePage();
      default:
        throw StateError('Unknown page index: $index');
    }
  }

  Widget _getPage(int index) =>
      _pageCache.putIfAbsent(index, () => _buildPage(index));

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _pageCount - 1);
    // Only build the initial page; all other pages are deferred.
    _getPage(_currentIndex);
    if (_currentIndex == 2) {
      _lexiWarmedUp = true;
      _warmupAiModels();
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: IndexedStack(
        index: _currentIndex,
        children: List.generate(_pageCount, (i) {
          // Use a lightweight placeholder until the tab is first visited.
          return _pageCache.containsKey(i)
              ? _pageCache[i]!
              : const SizedBox.shrink();
        }),
      ),
      bottomNavigationBar: Builder(
        builder: (context) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          return Container(
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDark : Colors.white,
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
                  setState(() {
                    _getPage(index); // build page lazily on first visit
                    _currentIndex = index;
                  });
                },
                items: [
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIcons.compass()),
                    activeIcon: Icon(
                      PhosphorIcons.compass(PhosphorIconsStyle.fill),
                    ),
                    label: 'Discovery',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIcons.bookOpen()),
                    activeIcon: Icon(
                      PhosphorIcons.bookOpen(PhosphorIconsStyle.fill),
                    ),
                    label: 'Learning',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIcons.bird()),
                    activeIcon: Icon(
                      PhosphorIcons.bird(PhosphorIconsStyle.fill),
                    ),
                    label: 'Lexi',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIcons.chatCircleText()),
                    activeIcon: Icon(
                      PhosphorIcons.chatCircleText(PhosphorIconsStyle.fill),
                    ),
                    label: 'Topic',
                  ),
                  BottomNavigationBarItem(
                    icon: Icon(PhosphorIcons.userCircle()),
                    activeIcon: Icon(
                      PhosphorIcons.userCircle(PhosphorIconsStyle.fill),
                    ),
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
    final endpoints = ['/ai/warmup', '/warmup'];

    for (final endpoint in endpoints) {
      try {
        final url = Uri.parse('${ApiConfig.aiServiceUrl}$endpoint');
        final response = await http
            .post(url)
            .timeout(const Duration(seconds: 8));

        if (response.statusCode >= 200 && response.statusCode < 300) {
          return;
        }
      } catch (_) {
        // Try next endpoint.
      }
    }
  }
}
