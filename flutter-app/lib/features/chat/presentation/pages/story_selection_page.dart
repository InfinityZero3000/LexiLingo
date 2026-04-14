import 'package:flutter/material.dart';
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
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.forum_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conversation Topics',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      '$total topics available',
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
                    ? const Center(child: CircularProgressIndicator())
                    : _buildStoryList(filteredStories, theme, isDark),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSearchBar(ThemeData theme, bool isDark) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        decoration: InputDecoration(
          hintText: 'Search topics...',
          hintStyle: TextStyle(
            color: isDark ? Colors.grey[500] : Colors.grey[400],
          ),
          prefixIcon: Icon(Icons.search, color: theme.primaryColor),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            vertical: 16,
            horizontal: 16,
          ),
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
            'All',
            _selectedDifficulty == null,
            () {
              setState(() => _selectedDifficulty = null);
            },
            theme,
            isDark,
          ),
          const SizedBox(width: 8),
          _buildChip(
            'Beginner',
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
            'Intermediate',
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
            'Advanced',
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.primaryColor
              : (isDark ? AppColors.surfaceDarkMuted : Colors.white),
          borderRadius: BorderRadius.circular(999),
          border: isSelected
              ? null
              : Border.all(color: theme.primaryColor.withValues(alpha: 0.2)),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: theme.primaryColor.withValues(alpha: 0.3),
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
                ? (isDark ? Colors.black : Colors.white)
                : (isDark ? Colors.grey[300] : Colors.grey[700]),
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
                  'Popular Scenarios',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                Text(
                  'See all',
                  style: TextStyle(
                    color: theme.primaryColor,
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
            'No topics found',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black54,
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
              color: theme.primaryColor.withValues(alpha: 0.05),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
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
                  color: theme.primaryColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  _getCategoryIcon(story.category),
                  color: theme.primaryColor,
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
                        color: isDark ? Colors.white : Colors.black87,
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
                          color: Colors.grey[500],
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${story.estimatedMinutes} mins',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[500],
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
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.chevron_right, color: theme.primaryColor, size: 24),
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
        return Colors.green;
      case DifficultyLevel.B1:
      case DifficultyLevel.B2:
        return Colors.blue;
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
