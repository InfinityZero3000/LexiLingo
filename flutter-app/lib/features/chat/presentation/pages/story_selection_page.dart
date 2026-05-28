import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import '../../data/models/story_model.dart';
import '../providers/story_provider.dart';
import 'topic_chat_page.dart';

/// Story Selection Page - Modern Redesign
class StorySelectionPage extends StatefulWidget {
  const StorySelectionPage({super.key});

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
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<StoryProvider>();
      provider.loadStories();
      provider.loadCategories();
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
    final accent = AppColorRoles.primary(isDark);

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        toolbarHeight: 86,
        backgroundColor: theme.scaffoldBackgroundColor,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Consumer<StoryProvider>(
          builder: (context, provider, _) {
            final total = provider.stories.length;
            return Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.forum_rounded,
                    color: Theme.of(context).colorScheme.surface,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'storySelection.pageTitle'.tr(),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColorRoles.textPrimary(isDark),
                      ),
                    ),
                    Text(
                      'storySelection.topicsAvailableCount'.tr(
                        namedArgs: {'total': '$total'},
                      ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? AppColors.textMuted
                            : AppColors.textGrey,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: const [],
      ),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          final filteredStories = provider.stories.where((s) {
            final matchesSearch =
                s.title.en.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                s.category.toLowerCase().contains(_searchQuery.toLowerCase());
            final matchesDifficulty =
                _selectedDifficulty == null ||
                s.difficultyLevel == _selectedDifficulty;
            return matchesSearch && matchesDifficulty;
          }).toList();

          return Column(
            children: [
              // Search Bar
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: _buildSearchBar(theme, isDark),
              ),

              // Filter Chips
              _buildFilterChips(theme, isDark),

              // Content
              Expanded(
                child: provider.isLoading && provider.stories.isEmpty
                    ? const Center(child: LottieLoadingWidget.medium())
                    : _buildStoryList(filteredStories, theme, isDark),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    final accent = AppColorRoles.primary(isDark);
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
        style: TextStyle(color: AppColorRoles.textPrimary(isDark)),
        decoration: InputDecoration(
          isDense: true,
          hintText: 'storySelection.searchHint'.tr(),
          hintStyle: TextStyle(color: AppColorRoles.textMuted(isDark)),
          prefixIcon: Icon(
            Icons.search,
            color: isDark ? accent : theme.primaryColor,
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 44,
            minHeight: 44,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.only(top: 0, bottom: 0, right: 16),
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
      padding: const EdgeInsets.all(16),
      itemCount: stories.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 16, top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'storySelection.popularScenariosTitle'.tr(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColorRoles.textPrimary(isDark),
                  ),
                ),
                Text(
                  'storySelection.seeAllLink'.tr(),
                  style: TextStyle(
                    color: isDark
                        ? AppColorRoles.primary(isDark)
                        : theme.primaryColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
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
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.search_off,
            size: 64,
            color: isDark ? Colors.grey[700] : Colors.grey[300],
          ),
          const SizedBox(height: 16),
          Text(
            'storySelection.noTopicsFound'.tr(),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _handleTopicSelection(StoryListItem story) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => TopicChatPage(story: story)),
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
    final difficultyColor = _getDifficultyColor(story.difficultyLevel);
    final difficultyLabel = _getDifficultyLabel(story.difficultyLevel);

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
                  _getCategoryIcon(story.category),
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
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: difficultyColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            difficultyLabel,
                            style: TextStyle(
                              color: difficultyColor,
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.timer_outlined,
                          size: 14,
                          color: AppColorRoles.textMuted(isDark),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${story.estimatedMinutes} mins',
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

  Color _getDifficultyColor(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.A1:
      case DifficultyLevel.A2:
        return AppColors.greenSuccessBright;
      case DifficultyLevel.B1:
      case DifficultyLevel.B2:
        return isDark ? AppColors.primaryDarkMode : AppColors.primary;
      case DifficultyLevel.C1:
      case DifficultyLevel.C2:
        return Colors.amber[700]!;
    }
  }

  String _getDifficultyLabel(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.A1:
      case DifficultyLevel.A2:
        return 'Beginner';
      case DifficultyLevel.B1:
      case DifficultyLevel.B2:
        return 'Intermediate';
      case DifficultyLevel.C1:
      case DifficultyLevel.C2:
        return 'Advanced';
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Icons.flight_takeoff;
      case 'business':
      case 'work':
        return Icons.work;
      case 'daily_life':
        return Icons.home;
      case 'food':
      case 'cafe':
        return Icons.coffee;
      case 'shopping':
        return Icons.shopping_cart;
      case 'health':
        return Icons.local_hospital;
      default:
        return Icons.chat_bubble;
    }
  }
}
