import 'package:easy_localization/easy_localization.dart';
import 'package:lexilingo_app/core/services/analytics_service.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../../domain/entities/story.dart';
import '../providers/story_provider.dart';
import '../utils/topic_icon_resolver.dart';
import 'topic_chat_page.dart';

/// Story Selection Page - Modern Redesign
class StorySelectionPage extends StatefulWidget {
  /// Offered from the empty state when no topics could be loaded; the hub
  /// passes this to flip back to free chat.
  final VoidCallback? onOpenFreeChat;

  /// True inside the Lexi tab, which already draws the header row: the page
  /// then has no AppBar and shows the topic count above the list instead.
  final bool embedded;

  const StorySelectionPage({
    super.key,
    this.onOpenFreeChat,
    this.embedded = false,
  });

  @override
  State<StorySelectionPage> createState() => _StorySelectionPageState();
}

class _StorySelectionPageState extends State<StorySelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  DifficultyLevel? _selectedDifficulty;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _load() {
    final provider = context.read<StoryProvider>();
    provider.loadStories();
    provider.loadCategories();
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _searchQuery = '';
      _selectedDifficulty = null;
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: widget.embedded
          ? null
          : AppBar(
              toolbarHeight: 64,
              backgroundColor: theme.scaffoldBackgroundColor,
              elevation: 0,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              automaticallyImplyLeading: false,
              titleSpacing: 20,
              title: Consumer<StoryProvider>(
                builder: (context, provider, _) {
                  final total = provider.stories.length;
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'storySelection.pageTitle'.tr(),
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        'storySelection.topicsAvailableCount'.tr(
                          namedArgs: {'total': '$total'},
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.stories.isEmpty) {
            return const Center(child: LottieLoadingWidget.medium());
          }
          // Search and level chips are pointless with nothing to filter.
          if (provider.stories.isEmpty) {
            return _buildNoTopicsState(theme, isDark);
          }

          final filteredStories = provider.stories.where((s) {
            final matchesSearch =
                s.title.en.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                s.category.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchesDifficulty =
                _selectedDifficulty == null ||
                s.difficultyLevel == _selectedDifficulty;
            return matchesSearch && matchesDifficulty;
          }).toList();

          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  // Search Bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                    child: _buildSearchBar(theme, isDark),
                  ),

                  // Filter Chips
                  _buildFilterChips(theme, isDark),

                  // Content
                  Expanded(
                    child: _buildStoryList(filteredStories, theme, isDark),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildNoTopicsState(ThemeData theme, bool isDark) {
    return _EmptyState(
      icon: Icons.forum_outlined,
      title: 'storySelection.emptyTitle'.tr(),
      body: 'storySelection.emptyBody'.tr(),
      actions: [
        FilledButton(
          onPressed: _load,
          child: Text('storySelection.retry'.tr()),
        ),
        if (widget.onOpenFreeChat != null)
          OutlinedButton(
            onPressed: widget.onOpenFreeChat,
            child: Text('storySelection.openFreeChat'.tr()),
          ),
      ],
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    final accent = AppColorRoles.primary(isDark);
    final bodyStyle = theme.textTheme.bodyLarge ?? const TextStyle();
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.backgroundDark.withValues(
              alpha: isDark ? 0.35 : 0.10,
            ),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        textAlignVertical: TextAlignVertical.center,
        style: bodyStyle.copyWith(color: AppColorRoles.textPrimary(isDark)),
        decoration: InputDecoration(
          hintText: 'storySelection.searchHint'.tr(),
          hintStyle: bodyStyle.copyWith(color: AppColorRoles.textMuted(isDark)),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 24,
            color: isDark ? accent : theme.primaryColor,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 56,
            minHeight: 56,
          ),
          filled: false,
          isCollapsed: true,
          contentPadding: const EdgeInsets.only(right: 16),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  Widget _buildFilterChips(ThemeData theme, bool isDark) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _buildChip(
            'storySelection.filterAll'.tr(),
            _selectedDifficulty == null,
            () {
              setState(() => _selectedDifficulty = null);
            },
            theme,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildChip(
            'storySelection.filterBeginner'.tr(),
            _selectedDifficulty == DifficultyLevel.A1 ||
                _selectedDifficulty == DifficultyLevel.A2,
            () {
              setState(() => _selectedDifficulty = DifficultyLevel.A1);
            },
            theme,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildChip(
            'storySelection.filterIntermediate'.tr(),
            _selectedDifficulty == DifficultyLevel.B1 ||
                _selectedDifficulty == DifficultyLevel.B2,
            () {
              setState(() => _selectedDifficulty = DifficultyLevel.B1);
            },
            theme,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildChip(
            'storySelection.filterAdvanced'.tr(),
            _selectedDifficulty == DifficultyLevel.C1 ||
                _selectedDifficulty == DifficultyLevel.C2,
            () {
              setState(() => _selectedDifficulty = DifficultyLevel.C1);
            },
            theme,
            isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildChip(
    String label,
    bool isSelected,
    VoidCallback onTap,
    ThemeData theme,
    bool isDark,
  ) {
    final accent = AppColorRoles.primary(isDark);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? accent
              : (isDark ? AppColors.surfaceDarkMuted : Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: isSelected
              ? null
              : Border.all(
                  color: (isDark ? accent : theme.primaryColor).withValues(
                    alpha: 0.2,
                  ),
                ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: (isDark ? accent : theme.primaryColor).withValues(
                      alpha: 0.3,
                    ),
                    blurRadius: 8,
                    offset: const Offset(0, 4),
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isSelected
                ? AppColors.slate900
                : AppColorRoles.textSecondary(isDark),
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _buildStoryList(
    List<StoryListItem> stories,
    ThemeData theme,
    bool isDark,
  ) {
    if (stories.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return ListView.builder(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: stories.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          // The "See all" label that sat here had no tap handler and the
          // list already shows every topic.
          return Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'storySelection.popularScenariosTitle'.tr(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
                if (widget.embedded)
                  Text(
                    'storySelection.topicsAvailableCount'.tr(
                      namedArgs: {
                        'total':
                            '${context.read<StoryProvider>().stories.length}',
                      },
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          );
        }

        final story = stories[index - 1];
        return _TopicListItem(
          story: story,
          onTap: () => _handleTopicSelection(story),
          theme: theme,
          isDark: isDark,
        );
      },
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return _EmptyState(
      icon: Icons.search_off,
      title: 'storySelection.noTopicsFound'.tr(),
      body: 'storySelection.noMatchBody'.tr(),
      actions: [
        TextButton(
          onPressed: _clearFilters,
          child: Text('storySelection.clearFilters'.tr()),
        ),
      ],
    );
  }

  Future<void> _handleTopicSelection(StoryListItem story) async {
    trackContentInteraction(
      itemType: 'topic',
      itemId: story.storyId,
      action: 'open',
      topic: story.category,
      source: 'story_selection',
    );
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TopicChatPage(story: story)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String body;
  final List<Widget> actions;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.body,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          32,
          24,
          32,
          24 + MediaQuery.paddingOf(context).bottom,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 56, color: AppColorRoles.textMuted(isDark)),
              const SizedBox(height: 16),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColorRoles.textPrimary(isDark),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: AppColorRoles.textSecondary(isDark),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopicListItem extends StatelessWidget {
  final StoryListItem story;
  final VoidCallback onTap;
  final ThemeData theme;
  final bool isDark;
  final bool isWarming;

  const _TopicListItem({
    required this.story,
    required this.onTap,
    required this.theme,
    required this.isDark,
    // ignore: unused_element_parameter
    this.isWarming = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color:
                  (isDark ? AppColorRoles.primary(isDark) : theme.primaryColor)
                      .withValues(alpha: isDark ? 0.20 : 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.backgroundDark.withValues(
                  alpha: isDark ? 0.25 : 0.08,
                ),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Icon
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color:
                      (isDark
                              ? AppColorRoles.primary(isDark)
                              : theme.primaryColor)
                          .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  TopicIconResolver.forStory(story),
                  color: isDark
                      ? AppColorRoles.primary(isDark)
                      : theme.primaryColor,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title.en,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: AppColorRoles.textPrimary(isDark),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        CefrBadge(level: story.difficultyLevel.shortName),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppColorRoles.textMuted(isDark),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'course.durationMin'.tr(
                            namedArgs: {'count': '${story.estimatedMinutes}'},
                          ),
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColorRoles.textMuted(isDark),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (isWarming)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: LottieLoadingWidget.tiny(),
                )
              else
                Icon(
                  Icons.chevron_right,
                  color: isDark
                      ? AppColorRoles.primary(isDark)
                      : theme.primaryColor,
                  size: 24,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
