import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
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
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../gamification/presentation/providers/gamification_provider.dart';
import '../../../gamification/presentation/widgets/starter_reward_dialog.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

const _tabs = <({IconData icon, IconData activeIcon, String label})>[
  (
    icon: PhosphorIconsRegular.compass,
    activeIcon: PhosphorIconsFill.compass,
    label: 'home.navDiscovery',
  ),
  (
    icon: PhosphorIconsRegular.graduationCap,
    activeIcon: PhosphorIconsFill.graduationCap,
    label: 'home.navLearning',
  ),
  (
    icon: PhosphorIconsRegular.sparkle,
    activeIcon: PhosphorIconsFill.sparkle,
    label: 'home.navLexi',
  ),
  (
    icon: PhosphorIconsRegular.chatCircleDots,
    activeIcon: PhosphorIconsFill.chatCircleDots,
    label: 'home.navTopic',
  ),
  (
    icon: PhosphorIconsRegular.userCircle,
    activeIcon: PhosphorIconsFill.userCircle,
    label: 'home.navAccount',
  ),
];

class _MainScreenState extends State<MainScreen> {
  late int _currentIndex;
  bool _lexiWarmedUp = false;
  bool _starterRewardChecked = false;

  // Pages are built lazily — only when the tab is first visited.
  static const int _pageCount = 5;
  static const int _lexiTab = 2;
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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _showPendingStarterReward();
    });
  }

  Future<void> _showPendingStarterReward() async {
    if (_starterRewardChecked || !mounted) return;
    _starterRewardChecked = true;

    final gamification = context.read<GamificationProvider>();
    final reward = await gamification.loadPendingStarterReward();
    if (!mounted || reward == null) return;

    await gamification.loadWallet();
    if (!mounted) return;
    await StarterRewardDialog.show(context, gems: reward.gemsAwarded);
    if (!mounted) return;

    final acknowledged = await gamification.acknowledgeStarterReward();
    if (!mounted || !acknowledged) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 4),
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        content: Row(
          children: [
            const Icon(Icons.diamond_rounded, color: AppColors.accentMint),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'gamification.starterReward.confirmation'.tr(
                  namedArgs: {'gems': '${reward.gemsAwarded}'},
                ),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurface,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
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
    final width = MediaQuery.sizeOf(context).width;
    final useRail = width >= 840;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      extendBody: true,
      body: useRail
          ? Row(
              children: [
                _buildNavigationRail(context, width),
                Expanded(child: _buildPageStack()),
              ],
            )
          : _buildPageStack(),
      bottomNavigationBar: useRail ? null : _buildBottomNavigationBar(context),
    );
  }

  Widget _buildPageStack() {
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(_pageCount, (i) {
        // Use a lightweight placeholder until the tab is first visited.
        if (!_pageCache.containsKey(i)) return const SizedBox.shrink();
        // Lexi keeps its mic and speaker; it has to be told when it is hidden.
        final page = i == _lexiTab
            ? LexiChatPage(isActive: _currentIndex == i)
            : _pageCache[i]!;
        return TickerMode(enabled: _currentIndex == i, child: page);
      }),
    );
  }

  void _selectTab(int index) {
    if (index == 2 && !_lexiWarmedUp) {
      _lexiWarmedUp = true;
      _warmupAiModels();
    }
    setState(() {
      _getPage(index); // build page lazily on first visit
      _currentIndex = index;
    });
  }

  Widget _buildNavigationRail(BuildContext context, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final extended = width >= 1100;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        border: Border(
          right: BorderSide(
            color: isDark ? AppColors.surfaceDarkMuted : AppColors.slate200,
          ),
        ),
      ),
      child: SafeArea(
        child: NavigationRail(
          selectedIndex: _currentIndex,
          extended: extended,
          minExtendedWidth: 190,
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.selected,
          onDestinationSelected: _selectTab,
          destinations: [
            for (final tab in _tabs)
              NavigationRailDestination(
                icon: Icon(tab.icon),
                selectedIcon: Icon(tab.activeIcon),
                label: Text(tab.label.tr()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomNavigationBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.4)
                  : Colors.black.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: BottomNavigationBar(
            currentIndex: _currentIndex,
            type: BottomNavigationBarType.fixed,
            elevation: 0,
            selectedFontSize: 11,
            unselectedFontSize: 11,
            selectedItemColor: AppColorRoles.primary(isDark),
            onTap: _selectTab,
            items: [
              for (final tab in _tabs)
                BottomNavigationBarItem(
                  icon: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(tab.icon, size: 24),
                  ),
                  activeIcon: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Icon(tab.activeIcon, size: 24),
                  ),
                  label: tab.label.tr(),
                ),
            ],
          ),
        ),
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
