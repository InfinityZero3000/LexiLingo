import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../data/models/story_model.dart';
import '../providers/story_provider.dart';
import 'topic_chat_page.dart';

/// Story Selection Page
/// Grid layout with cover images, difficulty badges, and category filters
class StorySelectionPage extends StatefulWidget {
  const StorySelectionPage({super.key});

  @override
  State<StorySelectionPage> createState() => _StorySelectionPageState();
}

class _StorySelectionPageState extends State<StorySelectionPage> {
  String? _selectedCategory;
  DifficultyLevel? _selectedDifficulty;

  @override
  void initState() {
    super.initState();
    // Load stories on init
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StoryProvider>().loadStories();
      context.read<StoryProvider>().loadCategories();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Choose a Topic'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterSheet,
            tooltip: 'Filter',
          ),
        ],
      ),
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          if (provider.isLoading && provider.stories.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (provider.error != null && provider.stories.isEmpty) {
            return _buildErrorView(provider.error!);
          }

          return RefreshIndicator(
            onRefresh: () => provider.loadStories(
              category: _selectedCategory,
              difficultyLevel: _selectedDifficulty,
            ),
            child: CustomScrollView(
              slivers: [
                // Category chips
                if (provider.categories.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _buildCategoryChips(provider.categories),
                  ),

                // Difficulty filter
                SliverToBoxAdapter(
                  child: _buildDifficultyFilter(),
                ),

                // Stories grid
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: _buildStoriesGrid(provider.filteredStories),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildErrorView(String error) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
          const SizedBox(height: 16),
          Text(
            'Failed to load stories',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => context.read<StoryProvider>().loadStories(),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips(List<String> categories) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          FilterChip(
            label: const Text('All'),
            selected: _selectedCategory == null,
            onSelected: (_) => _filterByCategory(null),
          ),
          const SizedBox(width: 8),
          ...categories.map((category) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(_capitalize(category)),
                  selected: _selectedCategory == category,
                  onSelected: (_) => _filterByCategory(category),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildDifficultyFilter() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          const Text('Level: ', style: TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('All'),
            selected: _selectedDifficulty == null,
            onSelected: (_) => _filterByDifficulty(null),
          ),
          const SizedBox(width: 8),
          ...DifficultyLevel.values.map((level) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ChoiceChip(
                  label: Text(level.shortName),
                  selected: _selectedDifficulty == level,
                  onSelected: (_) => _filterByDifficulty(level),
                  backgroundColor: _getDifficultyColor(level).withOpacity(0.2),
                  selectedColor: _getDifficultyColor(level),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildStoriesGrid(List<StoryListItem> stories) {
    if (stories.isEmpty) {
      return SliverToBoxAdapter(
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(height: 80),
              Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'No stories found',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Colors.grey.shade600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Try changing your filters',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      );
    }

    return SliverGrid(
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) => _StoryCard(
          story: stories[index],
          onTap: () => _openStory(stories[index]),
        ),
        childCount: stories.length,
      ),
    );
  }

  void _filterByCategory(String? category) {
    setState(() => _selectedCategory = category);
    context.read<StoryProvider>().setFilter(
          category: category,
          difficultyLevel: _selectedDifficulty,
        );
  }

  void _filterByDifficulty(DifficultyLevel? difficulty) {
    setState(() => _selectedDifficulty = difficulty);
    context.read<StoryProvider>().setFilter(
          category: _selectedCategory,
          difficultyLevel: difficulty,
        );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      builder: (context) => _FilterSheet(
        selectedCategory: _selectedCategory,
        selectedDifficulty: _selectedDifficulty,
        onApply: (category, difficulty) {
          _filterByCategory(category);
          _filterByDifficulty(difficulty);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _openStory(StoryListItem story) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => TopicChatPage(story: story),
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  Color _getDifficultyColor(DifficultyLevel level) {
    switch (level) {
      case DifficultyLevel.A1:
        return Colors.green;
      case DifficultyLevel.A2:
        return Colors.lightGreen;
      case DifficultyLevel.B1:
        return Colors.orange;
      case DifficultyLevel.B2:
        return Colors.deepOrange;
      case DifficultyLevel.C1:
        return Colors.red;
      case DifficultyLevel.C2:
        return Colors.purple;
    }
  }
}

/// Story card widget
class _StoryCard extends StatelessWidget {
  final StoryListItem story;
  final VoidCallback onTap;

  const _StoryCard({required this.story, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Cover image
            Expanded(
              flex: 3,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCoverImage(),
                  // Difficulty badge
                  Positioned(
                    top: 8,
                    right: 8,
                    child: _DifficultyBadge(level: story.difficultyLevel),
                  ),
                  // Category tag
                  Positioned(
                    bottom: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _capitalize(story.category),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Title and info
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      story.title.en,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: Colors.grey.shade600,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${story.estimatedMinutes} min',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey.shade600,
                              ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    if (story.coverImageUrl != null && story.coverImageUrl!.isNotEmpty) {
      return Image.network(
        story.coverImageUrl!,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) return child;
          return Container(
            color: Colors.grey.shade200,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
        errorBuilder: (context, error, stackTrace) => _buildPlaceholder(),
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: _getCategoryColor(story.category),
      child: Center(
        child: Icon(
          _getCategoryIcon(story.category),
          size: 48,
          color: Colors.white.withOpacity(0.8),
        ),
      ),
    );
  }

  Color _getCategoryColor(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Colors.blue.shade400;
      case 'business':
        return Colors.indigo.shade400;
      case 'daily_life':
        return Colors.teal.shade400;
      case 'food':
        return Colors.orange.shade400;
      case 'shopping':
        return Colors.pink.shade400;
      case 'health':
        return Colors.red.shade400;
      default:
        return Colors.grey.shade400;
    }
  }

  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case 'travel':
        return Icons.flight;
      case 'business':
        return Icons.business_center;
      case 'daily_life':
        return Icons.home;
      case 'food':
        return Icons.restaurant;
      case 'shopping':
        return Icons.shopping_bag;
      case 'health':
        return Icons.local_hospital;
      default:
        return Icons.chat_bubble;
    }
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

/// Difficulty badge widget
class _DifficultyBadge extends StatelessWidget {
  final DifficultyLevel level;

  const _DifficultyBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: _getColor(),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        level.shortName,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Color _getColor() {
    switch (level) {
      case DifficultyLevel.A1:
        return Colors.green;
      case DifficultyLevel.A2:
        return Colors.lightGreen.shade700;
      case DifficultyLevel.B1:
        return Colors.orange;
      case DifficultyLevel.B2:
        return Colors.deepOrange;
      case DifficultyLevel.C1:
        return Colors.red;
      case DifficultyLevel.C2:
        return Colors.purple;
    }
  }
}

/// Filter sheet widget
class _FilterSheet extends StatefulWidget {
  final String? selectedCategory;
  final DifficultyLevel? selectedDifficulty;
  final void Function(String?, DifficultyLevel?) onApply;

  const _FilterSheet({
    this.selectedCategory,
    this.selectedDifficulty,
    required this.onApply,
  });

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _category;
  late DifficultyLevel? _difficulty;

  @override
  void initState() {
    super.initState();
    _category = widget.selectedCategory;
    _difficulty = widget.selectedDifficulty;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Filter Stories',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 24),
          Text(
            'Difficulty Level',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _difficulty == null,
                onSelected: (_) => setState(() => _difficulty = null),
              ),
              ...DifficultyLevel.values.map((level) => ChoiceChip(
                    label: Text(level.shortName),
                    selected: _difficulty == level,
                    onSelected: (_) => setState(() => _difficulty = level),
                  )),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => widget.onApply(_category, _difficulty),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
