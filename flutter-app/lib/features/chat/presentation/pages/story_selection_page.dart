import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../auth/presentation/providers/auth_provider.dart';
import '../../data/models/story_model.dart';
import '../providers/story_provider.dart';
import '../widgets/topic_card.dart';
import 'topic_chat_page.dart';

/// Story Selection Page - Enhanced Version (Phase 3)
class StorySelectionPage extends StatefulWidget {
  const StorySelectionPage({super.key});

  @override
  State<StorySelectionPage> createState() => _StorySelectionPageState();
}

class _StorySelectionPageState extends State<StorySelectionPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String? _warmingStoryId;

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
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Consumer<StoryProvider>(
        builder: (context, provider, child) {
          final filteredStories = provider.filteredStories.where((s) {
            return s.title.en.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                   s.category.toLowerCase().contains(_searchQuery.toLowerCase());
          }).toList();

          return CustomScrollView(
            slivers: [
              // 1. App Bar with Title & Search
              _buildAppBar(),

              // 2. Search Bar
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: _buildSearchBar(),
                ),
              ),

              // 3. Recently Used Section
              if (provider.recentlyUsed.isNotEmpty) ...[
                _buildSectionHeader('Recently Used'),
                SliverToBoxAdapter(
                  child: SizedBox(
                    height: 180,
                    child: ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: provider.recentlyUsed.length,
                      itemBuilder: (context, index) {
                        final story = provider.recentlyUsed[index];
                        return SizedBox(
                          width: 160,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: TopicCard(
                              story: story,
                              isWarming: provider.isWarming && _warmingStoryId == story.storyId,
                              onTap: () => _handleTopicSelection(story),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],

              // 4. All Topics Section
              _buildSectionHeader('All Topics'),
              
              if (provider.isLoading && provider.stories.isEmpty)
                const SliverFillRemaining(
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (filteredStories.isEmpty)
                SliverFillRemaining(
                  child: _buildEmptyState(),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverGrid(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 0.75,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final story = filteredStories[index];
                        return TopicCard(
                          story: story,
                          isWarming: provider.isWarming && _warmingStoryId == story.storyId,
                          onTap: () => _handleTopicSelection(story),
                        );
                      },
                      childCount: filteredStories.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 120,
      pinned: true,
      backgroundColor: Colors.white,
      elevation: 0,
      flexibleSpace: FlexibleSpaceBar(
        titlePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        centerTitle: false,
        title: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Chat with AI',
              style: TextStyle(
                color: Colors.black,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
            Text(
              'Choose a topic to get started',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.filter_list, color: Colors.black),
          onPressed: _showFilterSheet,
        ),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Search topics...',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isNotEmpty 
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              )
            : null,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off, size: 64, color: Colors.grey[300]),
          const SizedBox(height: 16),
          const Text('No topics found', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Try searching for something else', style: TextStyle(color: Colors.grey[600])),
        ],
      ),
    );
  }

  Future<void> _handleTopicSelection(StoryListItem story) async {
    final provider = context.read<StoryProvider>();
    final authProvider = context.read<AuthProvider>();
    final userId = authProvider.user?.id ?? 'guest';

    setState(() => _warmingStoryId = story.storyId);

    // Phase 2.3: Warm cache first
    final success = await provider.warmTopicCache(
      storyId: story.storyId,
      userId: userId,
    );

    if (!mounted) return;

    if (success) {
      // Navigate to chat
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => TopicChatPage(story: story),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to prepare AI context. Please try again.')),
      );
    }

    setState(() => _warmingStoryId = null);
  }

  void _showFilterSheet() {
    final provider = context.read<StoryProvider>();
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => _FilterSheet(
        selectedCategory: provider.filterCategory,
        selectedDifficulty: provider.filterDifficulty,
        onApply: (category, difficulty) {
          provider.setFilter(category: category, difficultyLevel: difficulty);
          Navigator.pop(context);
        },
      ),
    );
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
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('Filter Topics', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 24),
          const Text('Difficulty Level', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('All'),
                selected: _difficulty == null,
                onSelected: (_) => setState(() => _difficulty = null),
              ),
              ...DifficultyLevel.values.map(
                (level) => ChoiceChip(
                  label: Text(level.shortName),
                  selected: _difficulty == level,
                  onSelected: (_) => setState(() => _difficulty = level),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () {
                    setState(() {
                      _category = null;
                      _difficulty = null;
                    });
                  },
                  child: const Text('Reset'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: () => widget.onApply(_category, _difficulty),
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
