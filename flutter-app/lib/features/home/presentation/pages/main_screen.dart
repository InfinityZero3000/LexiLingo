import 'package:lexilingo_app/core/utils/freshness.dart';
import 'package:lexilingo_app/features/progress/presentation/providers/progress_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../chat/presentation/providers/story_provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/core/navigation/deferred_prefetch.dart';
import 'home_page.dart';
import '../../../course/presentation/screens/course_list_screen.dart';
import '../../../practice/presentation/pages/practice_lab_page.dart';
import '../../../profile/presentation/pages/profile_page.dart';
import '../../../lexi_chat/presentation/pages/lexi_hub_page.dart';
import 'package:lexilingo_app/core/network/api_config.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../gamification/presentation/providers/gamification_provider.dart';
import '../../../gamification/presentation/widgets/starter_reward_dialog.dart';
import '../../../level/presentation/providers/level_provider.dart';
import '../../../progress/presentation/providers/streak_provider.dart';
import 'package:lexilingo_app/core/services/app_navigation_service.dart';
import '../../domain/progressive_unlock.dart';
import '../providers/home_provider.dart';

class MainScreen extends StatefulWidget {
  final int initialIndex;

  const MainScreen({super.key, this.initialIndex = 0});

  static const int learningTab = 1;
  static const int lexiTab = 2;

  /// Switches the enclosing MainScreen to [index]; false when there is none.
  static bool switchTab(BuildContext context, int index) {
    final state = context.findAncestorStateOfType<_MainScreenState>();
    if (state == null) return false;
    state._selectTab(index);
    return true;
  }

  /// Bottom scroll clearance so content clears the floating bottom bar on
  /// compact phones (including iPhone 7/8 with zero home-indicator inset).
  static double bottomBarClearance(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final bottomPadding = MediaQuery.paddingOf(context).bottom;
    if (width >= 840) return bottomPadding + 24;
    return bottomPadding + 88;
  }

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
    icon: PhosphorIconsRegular.flask,
    activeIcon: PhosphorIconsFill.flask,
    label: 'home.navPracticeLab',
  ),
  (
    icon: PhosphorIconsRegular.userCircle,
    activeIcon: PhosphorIconsFill.userCircle,
    label: 'home.navAccount',
  ),
];

/// Signed out, every progress request would go out with no token and 401, and
/// popping back to this screen during a sign-out is exactly when that happens.
@visibleForTesting
bool progressRefreshDue({
  required bool authenticated,
  required DateTime? last,
  required DateTime now,
}) =>
    authenticated &&
    (last == null || now.difference(last) >= const Duration(seconds: 2));

class _MainScreenState extends State<MainScreen>
    with RouteAware, SingleTickerProviderStateMixin {
  late int _currentIndex;
  late final AnimationController _tabSwitch = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 380),
    value: 1,
  );
  late final Animation<double> _tabCurve = CurvedAnimation(
    parent: _tabSwitch,
    curve: Curves.easeOutCubic,
  );
  bool _lexiWarmedUp = false;
  bool _starterRewardChecked = false;

  // Pages are built lazily — only when the tab is first visited.
  static const int _pageCount = 5;
  static const int _lexiTab = 2;
  static const int _profileTab = 4;
  final Map<int, Widget> _pageCache = {};
  DateTime? _lastProgressRefresh;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route != null)
      AppNavigationService.routeObserver.subscribe(this, route);
  }

  @override
  void dispose() {
    AppNavigationService.routeObserver.unsubscribe(this);
    _tabSwitch.dispose();
    super.dispose();
  }

  @override
  void didPopNext() => _refreshProgress(afterActivity: true);

  // A tab switch is passive and may reuse data loaded moments ago; coming back
  // from a pushed screen (a lesson, a game) is not, so it always refetches.
  void _refreshProgress({bool afterActivity = false}) {
    final now = DateTime.now();
    if (!progressRefreshDue(
      authenticated: context.read<AuthProvider>().isAuthenticated,
      last: _lastProgressRefresh,
      now: now,
    )) {
      return;
    }
    _lastProgressRefresh = now;
    final maxAge = afterActivity ? null : kPassiveReloadWindow;
    context.read<HomeProvider>().refreshWeeklyProgressSilently(maxAge: maxAge);
    context.read<LevelProvider>().fetchLevelFull(maxAge: maxAge);
    context.read<StreakProvider>().loadStreak(maxAge: maxAge);
    final auth = context.read<AuthProvider>();
    if (afterActivity) {
      auth.invalidateFreshness();
      context.read<ProgressProvider>().invalidateFreshness();
    }
    if (secondaryFeaturesLocked(
      flagEnabled: ApiConfig.progressiveUnlock,
      lessonsCompleted: auth.currentUser?.lessonsCompleted,
      totalXp: auth.currentUser?.totalXp,
    )) {
      auth.refreshCurrentUser(maxAge: maxAge);
    }
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const HomePageNew();
      case 1:
        return const CourseListScreen();
      case 2:
        return const LexiHubPage();
      case 3:
        return const PracticeLabPage();
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
      // Model warm-up is not first-paint data; let the first frame's requests go first.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future<void>.delayed(const Duration(seconds: 1), () {
          if (mounted) _warmupAiModels();
        });
      });
    }
    _triggerPreWarming();
    prefetchDeferredFeatures(
      isSignedIn: () => mounted && context.read<AuthProvider>().isAuthenticated,
    );
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
    return FadeTransition(
      opacity: Tween<double>(begin: 0.65, end: 1).animate(_tabCurve),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.015),
          end: Offset.zero,
        ).animate(_tabCurve),
        child: _buildIndexedPages(),
      ),
    );
  }

  Widget _buildIndexedPages() {
    return IndexedStack(
      index: _currentIndex,
      children: List.generate(_pageCount, (i) {
        // Use a lightweight placeholder until the tab is first visited.
        if (!_pageCache.containsKey(i)) return const SizedBox.shrink();
        // Lexi keeps its mic and speaker; it has to be told when it is hidden.
        final page = switch (i) {
          _lexiTab => LexiHubPage(isActive: _currentIndex == i),
          // The tab stays mounted, so Profile reloads when it is selected.
          _profileTab => ProfilePage(isActive: _currentIndex == i),
          _ => _pageCache[i]!,
        };
        return TickerMode(enabled: _currentIndex == i, child: page);
      }),
    );
  }

  void _selectTab(int index) {
    if (index == 2 && !_lexiWarmedUp) {
      _lexiWarmedUp = true;
      _warmupAiModels();
    }
    final changed = index != _currentIndex;
    if (changed && !MediaQuery.disableAnimationsOf(context)) {
      _tabSwitch.forward(from: 0);
    }
    setState(() {
      _getPage(index); // build page lazily on first visit
      _currentIndex = index;
    });
    if (changed && (index == 0 || index == _profileTab)) _refreshProgress();
  }

  Widget _buildNavigationRail(BuildContext context, double width) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surface = Theme.of(context).colorScheme.surface;
    final extended = width >= 1100;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: surface,
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final selectedColor = AppColorRoles.primary(isDark);
    return SafeArea(
      minimum: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.md,
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl + AppSpacing.sm),
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
        child: SizedBox(
          height: 44,
          child: LayoutBuilder(
            builder: (context, constraints) {
              const pillWidth = 52.0;
              final cell = constraints.maxWidth / _tabs.length;
              return Stack(
                children: [
                  AnimatedPositioned(
                    duration: const Duration(milliseconds: 460),
                    curve: Curves.easeInOutCubic,
                    left: cell * _currentIndex + (cell - pillWidth) / 2,
                    top: 0,
                    width: pillWidth,
                    height: 44,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: selectedColor.withValues(alpha: 0.14),
                        borderRadius: AppRadius.pillAll,
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _tabs.length; i++)
                        Expanded(
                          child: Semantics(
                            button: true,
                            selected: i == _currentIndex,
                            label: _tabs[i].label.tr(),
                            child: Tooltip(
                              message: _tabs[i].label.tr(),
                              child: InkResponse(
                                onTap: () => _selectTab(i),
                                radius: 32,
                                child: SizedBox(
                                  height: 44,
                                  child: Center(
                                    child: AnimatedScale(
                                      scale: i == _currentIndex ? 1.12 : 1,
                                      duration: const Duration(
                                        milliseconds: 380,
                                      ),
                                      curve: Curves.easeOutCubic,
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 280,
                                        ),
                                        child: Icon(
                                          i == _currentIndex
                                              ? _tabs[i].activeIcon
                                              : _tabs[i].icon,
                                          key: ValueKey(i == _currentIndex),
                                          size: 26,
                                          color: i == _currentIndex
                                              ? selectedColor
                                              : theme
                                                    .colorScheme
                                                    .onSurfaceVariant,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              );
            },
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
