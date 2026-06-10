import 'dart:async';
import 'package:flutter/material.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/flashcard_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/screens/flashcard_review_screen.dart';

class VocabLibraryPage extends StatefulWidget {
  const VocabLibraryPage({super.key});

  @override
  State<VocabLibraryPage> createState() => _VocabLibraryPageState();
}

class _VocabLibraryPageState extends State<VocabLibraryPage> {
  final TextEditingController _searchController = TextEditingController();

  static const Map<String, _TagMeta> _tagMeta = {
    'general':    _TagMeta(label: 'Tổng quát',  icon: Icons.hearing_rounded),
    'travel':     _TagMeta(label: 'Du lịch',    icon: Icons.flight),
    'business':   _TagMeta(label: 'Kinh doanh', icon: Icons.work),
    'daily':      _TagMeta(label: 'Hàng ngày',  icon: Icons.coffee),
    'science':    _TagMeta(label: 'Khoa học',   icon: Icons.science_rounded),
    'technology': _TagMeta(label: 'Công nghệ',  icon: Icons.devices_rounded),
    'ielts':      _TagMeta(label: 'IELTS',       icon: Icons.school_rounded),
    'academic':   _TagMeta(label: 'Học thuật',  icon: Icons.menu_book_rounded),
    'health':     _TagMeta(label: 'Sức khỏe',   icon: Icons.health_and_safety_rounded),
    'food':       _TagMeta(label: 'Ẩm thực',    icon: Icons.restaurant_rounded),
    'sports':     _TagMeta(label: 'Thể thao',   icon: Icons.sports_rounded),
    'daily_life': _TagMeta(label: 'Hàng ngày',  icon: Icons.coffee_rounded),
    'government': _TagMeta(label: 'Chính phủ',  icon: Icons.gavel_rounded),
    'economics':  _TagMeta(label: 'Kinh tế',    icon: Icons.monetization_on_rounded),
    'education':  _TagMeta(label: 'Giáo dục',   icon: Icons.school_rounded),
    'lesson':     _TagMeta(label: 'Bài học',    icon: Icons.import_contacts_rounded),
    'philosophy': _TagMeta(label: 'Triết học',  icon: Icons.psychology_rounded),
    'basic_200':  _TagMeta(label: 'Từ cơ bản',  icon: Icons.star_outline_rounded),
    'nature':     _TagMeta(label: 'Tự nhiên',   icon: Icons.nature_people_rounded),
    'core-vocab': _TagMeta(label: 'Cốt lõi',    icon: Icons.grade_rounded),
    'auto':       _TagMeta(label: 'Tự động lưu', icon: Icons.bolt_rounded),
    'crawl':      _TagMeta(label: 'Thu thập',    icon: Icons.download_rounded),
    'society':    _TagMeta(label: 'Xã hội',     icon: Icons.people_rounded),
    'seed':       _TagMeta(label: 'Mầm',        icon: Icons.spa_rounded),
    'history':    _TagMeta(label: 'Lịch sử',    icon: Icons.history_edu_rounded),
  };

  @override
  Widget build(BuildContext context) {
    final vocabProvider = Provider.of<VocabProvider>(context);
    final List<VocabWord> words = vocabProvider.filteredWords;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text('vocabulary.library'.tr()),
          centerTitle: true,
          leading: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              margin: const EdgeInsets.all(8),
              decoration: const BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.arrow_back_ios,
                color: AppColors.primary,
                size: 20,
              ),
            ),
          ),
          actions: [
            GestureDetector(
              onTap: () => _showAddWordDialog(context, vocabProvider),
              child: Container(
                margin: const EdgeInsets.only(right: 16),
                child: const Icon(
                  Icons.add_circle,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
            ),
          ],
          bottom: TabBar(
            indicatorColor: AppColors.primary,
            labelColor: AppColors.primary,
            unselectedLabelColor: Colors.grey,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold),
            tabs: [
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.list_alt_rounded, size: 20),
                    const SizedBox(width: 8),
                    Text('vocabulary.tabWords'.tr()),
                  ],
                ),
              ),
              Tab(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.style_outlined, size: 20),
                    const SizedBox(width: 8),
                    Text('vocabulary.tabTopics'.tr()),
                  ],
                ),
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            // Tab 1: Words
            Column(
              children: [
                // Search Bar
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Container(
                    height: 48,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 2,
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(left: 12, right: 8),
                          child: Icon(
                            Icons.search,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            decoration: InputDecoration(
                              hintText: 'vocabulary.searchPlaceholder'.tr(),
                              border: InputBorder.none,
                              hintStyle: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Filters
                _buildTopicFilterBar(context, vocabProvider),

                // Words Header
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        vocabProvider.selectedTag == null
                            ? 'vocabulary.recentWordsHeader'.tr()
                            : (_tagMeta[vocabProvider.selectedTag]?.label ??
                                    _capitalizeTag(vocabProvider.selectedTag!))
                                .toUpperCase(),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (!vocabProvider.isLoading)
                        Text(
                          '${words.length} từ',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),

                // List
                Expanded(
                  child: vocabProvider.isLoading
                      ? _buildSkeletonList()
                      : words.isEmpty
                      ? EmptyStateWidget.vocabulary(
                          onAdd: () => _showAddWordDialog(context, vocabProvider),
                        )
                      : RefreshIndicator(
                          onRefresh: () => vocabProvider.loadWords(),
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: words.length,
                            itemBuilder: (context, index) {
                              final word = words[index];
                              return _buildWordCard(context, word);
                            },
                          ),
                        ),
                ),
              ],
            ),
            // Tab 2: Topics
            _buildTopicFlashcardsTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicFlashcardsTab(BuildContext context) {
    final vocabProvider = Provider.of<VocabProvider>(context);
    final customDecks = vocabProvider.decks;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section 1: System Topics Header
          Text(
            'vocabulary.systemTopicsHeader'.tr(),
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 12),

          // Grid for system topics
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: _topics.length,
            itemBuilder: (context, index) {
              final topic = _topics[index];
              return _buildTopicCard(context, topic);
            },
          ),

          const SizedBox(height: 24),

          // Section 2: Custom Decks Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'vocabulary.customDecksHeader'.tr(),
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              IconButton(
                icon: const Icon(Icons.add, color: AppColors.primary),
                onPressed: () => _showCreateDeckDialog(context, vocabProvider),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Grid for custom decks
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
              childAspectRatio: 0.85,
            ),
            itemCount: customDecks.length + 1, // +1 for the "Create Deck" card
            itemBuilder: (context, index) {
              if (index == customDecks.length) {
                return _buildCreateDeckCard(context, vocabProvider);
              }
              final deck = customDecks[index];
              return _buildCustomDeckCard(context, deck, vocabProvider);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCustomDeckCard(
    BuildContext context,
    VocabularyDeck deck,
    VocabProvider vocabProvider,
  ) {
    Color deckColor;
    try {
      final hex = deck.color.replaceAll('#', '');
      deckColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) {
      deckColor = AppColors.primary;
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: [deckColor, deckColor.withValues(alpha: 0.7)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: deckColor.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onLongPress: () => _showDeleteDeckConfirmation(context, deck, vocabProvider),
          onTap: () => _startDeckStudy(context, deck),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Positioned(
                right: -15,
                bottom: -15,
                child: Transform.rotate(
                  angle: -0.25,
                  child: Icon(
                    Icons.collections_bookmark_rounded,
                    size: 90,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.collections_bookmark_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                          onPressed: () => _showDeleteDeckConfirmation(context, deck, vocabProvider),
                          constraints: const BoxConstraints(),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      deck.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${deck.itemCount} ${'vocabulary.wordsCount'.tr(args: [deck.itemCount.toString()])}',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'vocabulary.startLearning'.tr(),
                            style: TextStyle(
                              color: deckColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.play_arrow_rounded,
                            color: deckColor,
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCreateDeckCard(BuildContext context, VocabProvider vocabProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.white24 : Colors.black12,
          width: 2,
          style: BorderStyle.solid,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _showCreateDeckDialog(context, vocabProvider),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_rounded,
                  size: 40,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
                const SizedBox(height: 8),
                Text(
                  'vocabulary.createCustomDeck'.tr(),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showCreateDeckDialog(BuildContext context, VocabProvider vocabProvider) {
    final nameController = TextEditingController();
    final descController = TextEditingController();
    String selectedColor = '#2196F3';

    final List<String> colors = [
      '#2196F3', // Blue
      '#4CAF50', // Green
      '#FF9800', // Orange
      '#E91E63', // Pink
      '#9C27B0', // Purple
      '#9E9E9E', // Grey
    ];

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text('vocabulary.createNewDeck'.tr()),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'vocabulary.deckName'.tr(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descController,
                      decoration: InputDecoration(
                        labelText: 'vocabulary.deckDescription'.tr(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'vocabulary.selectColor'.tr(),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: 48,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: colors.length,
                        itemBuilder: (context, index) {
                          final colorHex = colors[index];
                          final color = Color(int.parse('FF${colorHex.replaceAll('#', '')}', radix: 16));
                          final isSelected = selectedColor == colorHex;

                          return GestureDetector(
                            onTap: () {
                              setState(() {
                                selectedColor = colorHex;
                              });
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 8),
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: color,
                                shape: BoxShape.circle,
                                border: isSelected
                                    ? Border.all(color: Colors.black, width: 3)
                                    : null,
                              ),
                              child: isSelected
                                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                                  : null,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('common.cancel'.tr()),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.trim().isEmpty) return;
                    final success = await vocabProvider.createDeck(
                      nameController.text.trim(),
                      descController.text.trim().isEmpty ? null : descController.text.trim(),
                      selectedColor,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                      if (!success) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(vocabProvider.errorMessage ?? 'vocabulary.createDeckFailed'.tr()),
                            backgroundColor: AppColors.errorBright,
                          ),
                        );
                      }
                    }
                  },
                  child: Text('common.create'.tr()),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteDeckConfirmation(
    BuildContext context,
    VocabularyDeck deck,
    VocabProvider vocabProvider,
  ) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('vocabulary.deleteDeckTitle'.tr()),
          content: Text(
            'vocabulary.deleteDeckPrompt'.tr(args: [deck.name]),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('common.cancel'.tr()),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.errorBright,
                foregroundColor: Colors.white,
              ),
              onPressed: () async {
                final success = await vocabProvider.deleteDeck(deck.id);
                if (context.mounted) {
                  Navigator.pop(context);
                  if (!success) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(vocabProvider.errorMessage ?? 'vocabulary.deleteDeckFailed'.tr()),
                        backgroundColor: AppColors.errorBright,
                      ),
                    );
                  }
                }
              },
              child: Text('common.delete'.tr()),
            ),
          ],
        );
      },
    );
  }

  Future<void> _startDeckStudy(BuildContext context, VocabularyDeck deck) async {
    final flashcardProvider = Provider.of<FlashcardProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );

    try {
      await flashcardProvider.startDeckSession(deckId: deck.id);
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        if (flashcardProvider.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(flashcardProvider.errorMessage!),
              backgroundColor: AppColors.errorBright,
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FlashcardReviewScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('vocabulary.startStudyFailed'.tr()),
            backgroundColor: AppColors.errorBright,
          ),
        );
      }
    }
  }

  Widget _buildTopicCard(BuildContext context, _TopicConfig topic) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          colors: topic.gradient,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: topic.gradient[0].withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _startTopicStudy(context, topic),
          child: Stack(
            clipBehavior: Clip.antiAlias,
            children: [
              Positioned(
                top: -30,
                right: -30,
                child: Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.1),
                  ),
                ),
              ),
              Positioned(
                right: -15,
                bottom: -15,
                child: Transform.rotate(
                  angle: -0.25,
                  child: Icon(
                    topic.icon,
                    size: 90,
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        topic.icon,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      topic.titleKey.tr(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      topic.subtitleKey.tr(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'vocabulary.startLearning'.tr(),
                            style: TextStyle(
                              color: topic.gradient[0],
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.play_arrow_rounded,
                            color: topic.gradient[0],
                            size: 14,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _startTopicStudy(BuildContext context, _TopicConfig topic) async {
    final flashcardProvider = Provider.of<FlashcardProvider>(context, listen: false);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
        ),
      ),
    );

    try {
      await flashcardProvider.startTopicSession(tag: topic.tag);
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        if (flashcardProvider.errorMessage != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(flashcardProvider.errorMessage!),
              backgroundColor: AppColors.errorBright,
            ),
          );
        } else {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => const FlashcardReviewScreen(),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context); // Dismiss loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('vocabulary.startStudyFailed'.tr()),
            backgroundColor: AppColors.errorBright,
          ),
        );
      }
    }
  }

  Widget _buildTopicFilterBar(BuildContext context, VocabProvider vocabProvider) {
    final availableTags = vocabProvider.availableTags;
    final selectedTag = vocabProvider.selectedTag;

    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            'vocabulary.filterAll'.tr(),
            selectedTag == null,
            onTap: () => vocabProvider.setTagFilter(null),
          ),
          ...availableTags.map((tag) {
            final meta = _tagMeta[tag];
            return Padding(
              padding: const EdgeInsets.only(left: 8),
              child: _buildFilterChip(
                meta?.label ?? _capitalizeTag(tag),
                selectedTag == tag,
                icon: meta?.icon,
                onTap: () => vocabProvider.setTagFilter(
                  selectedTag == tag ? null : tag,
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  String _capitalizeTag(String tag) =>
      tag.isEmpty ? tag : tag[0].toUpperCase() + tag.substring(1);

  Widget _buildFilterChip(
    String label,
    bool isSelected, {
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: EdgeInsets.symmetric(
          horizontal: icon != null ? 10 : 14,
          vertical: 8,
        ),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary
              : (isDark ? Colors.white.withValues(alpha: 0.06) : AppColors.grey100),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 14,
                color: isSelected ? Colors.white : AppColors.textGrey,
              ),
              const SizedBox(width: 5),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected
                    ? Colors.white
                    : (isDark ? Colors.white70 : AppColors.textDark),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWordCard(BuildContext context, VocabWord vocabWord) {
    final colorScheme = Theme.of(context).colorScheme;
    final word = vocabWord.word;
    final ipa = vocabWord.pronunciation ?? '';
    final def = vocabWord.definition;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(color: Colors.transparent),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => showVocabWordDetail(context, vocabWord),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          Icons.menu_book,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.baseline,
                              textBaseline: TextBaseline.alphabetic,
                              children: [
                                Text(
                                  word,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 18,
                                  ),
                                ),
                                if (ipa.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    ipa,
                                    style: TextStyle(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.7,
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Builder(builder: (context) {
                              final displayDef = def.isEmpty
                                  ? 'vocabulary.noDefinitionYet'.tr()
                                  : def;
                              return Text(
                                displayDef,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: def.isEmpty
                                      ? Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant
                                            .withValues(alpha: 0.45)
                                      : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  fontSize: 14,
                                  fontStyle: def.isEmpty
                                      ? FontStyle.italic
                                      : FontStyle.normal,
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showAddWordDialog(BuildContext context, VocabProvider provider) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddWordSheet(provider: provider),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: 6,
      itemBuilder: (context, index) => const SkeletonVocabCard(),
    );
  }
}

// ─── Add Word Bottom Sheet ────────────────────────────────────────────────────

class _AddWordSheet extends StatefulWidget {
  final VocabProvider provider;
  const _AddWordSheet({required this.provider});

  @override
  State<_AddWordSheet> createState() => _AddWordSheetState();
}

class _AddWordSheetState extends State<_AddWordSheet> {
  final _wordController = TextEditingController();
  final _defController = TextEditingController();
  final _exampleController = TextEditingController();

  Timer? _debounce;
  bool _isLooking = false;
  bool? _wordFound; // null = not checked, true = found, false = not found
  String? _ipa;
  String? _audioUrl;
  String? _partOfSpeech;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _wordController.addListener(_onWordChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _wordController.dispose();
    _defController.dispose();
    _exampleController.dispose();
    super.dispose();
  }

  void _onWordChanged() {
    final text = _wordController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _wordFound = null;
        _ipa = null;
        _audioUrl = null;
        _partOfSpeech = null;
        _isLooking = false;
      });
      _debounce?.cancel();
      return;
    }

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), () async {
      setState(() => _isLooking = true);
      final result = await widget.provider.lookupWord(text);
      if (!mounted) return;
      setState(() {
        _isLooking = false;
        _wordFound = result.found;
        _ipa = result.pronunciation;
        _audioUrl = result.audioUrl;
        _partOfSpeech = result.partOfSpeech;
        // Auto-fill if fields are empty
        if (result.found) {
          if (_defController.text.isEmpty && result.definition != null) {
            _defController.text = result.definition!;
          }
          if (_exampleController.text.isEmpty && result.example != null) {
            _exampleController.text = result.example!;
          }
        }
      });
    });
  }

  Future<void> _save() async {
    final word = _wordController.text.trim();
    final def = _defController.text.trim();
    if (word.isEmpty || def.isEmpty) return;

    setState(() => _saving = true);
    final ok = await widget.provider.addWord(
      word,
      def,
      pronunciation: _ipa,
      audioUrl: _audioUrl,
      example: _exampleController.text.trim().isEmpty
          ? null
          : _exampleController.text.trim(),
      partOfSpeech: _partOfSpeech,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            widget.provider.errorMessage ?? 'vocabulary.failedToSaveWord'.tr(),
          ),
          backgroundColor: AppColors.errorBright,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(24, 16, 24, 24 + bottomPadding),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Text(
            'vocabulary.addNewWord'.tr(),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 20),

          // Word field + spell-check indicator
          TextField(
            controller: _wordController,
            autofocus: true,
            textCapitalization: TextCapitalization.none,
            style: TextStyle(fontSize: 16, color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'vocabulary.wordLabel'.tr(),
              hintText: 'vocabulary.wordInputHint'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Icon(Icons.abc_rounded),
              suffixIcon: _buildWordStatus(),
            ),
          ),

          // IPA + part-of-speech row
          if (_ipa != null || _partOfSpeech != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (_ipa != null)
                  _InfoChip(
                    icon: Icons.record_voice_over_outlined,
                    label: _ipa!,
                    color: AppColors.primary,
                  ),
                if (_ipa != null && _partOfSpeech != null)
                  const SizedBox(width: 8),
                if (_partOfSpeech != null)
                  _InfoChip(
                    icon: Icons.label_outline,
                    label: _partOfSpeech!,
                    color: isDark ? Colors.teal : Colors.teal.shade700,
                  ),
              ],
            ),
          ],

          const SizedBox(height: 16),

          // Definition field
          TextField(
            controller: _defController,
            maxLines: 3,
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'vocabulary.definition'.tr(),
              hintText: 'vocabulary.definitionHint'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 40),
                child: Icon(Icons.menu_book_outlined),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Example field
          TextField(
            controller: _exampleController,
            maxLines: 2,
            style: TextStyle(fontSize: 15, color: cs.onSurface),
            decoration: InputDecoration(
              labelText: 'vocabulary.exampleSentenceLabel'.tr(),
              hintText: 'vocabulary.exampleSentenceHint'.tr(),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              prefixIcon: const Padding(
                padding: EdgeInsets.only(bottom: 24),
                child: Icon(Icons.format_quote_outlined),
              ),
            ),
          ),

          const SizedBox(height: 24),

          // Action buttons
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text('common.cancel'.tr()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          'vocabulary.saveWord'.tr(),
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget? _buildWordStatus() {
    if (_isLooking) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_wordFound == true) {
      return const Icon(Icons.check_circle_rounded, color: Colors.green);
    }
    if (_wordFound == false) {
      return Tooltip(
        message: 'vocabulary.wordNotFound'.tr(),
        child: Icon(Icons.warning_amber_rounded, color: Colors.orange.shade700),
      );
    }
    return null;
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TagMeta {
  final String label;
  final IconData icon;
  const _TagMeta({required this.label, required this.icon});
}

class _TopicConfig {
  final String titleKey;
  final String tag;
  final String subtitleKey;
  final IconData icon;
  final List<Color> gradient;

  const _TopicConfig({
    required this.titleKey,
    required this.tag,
    required this.subtitleKey,
    required this.icon,
    required this.gradient,
  });
}

const List<_TopicConfig> _topics = [
  _TopicConfig(
    titleKey: 'vocabulary.topicGeneral',
    tag: 'general',
    subtitleKey: 'vocabulary.topicGeneralSubtitle',
    icon: Icons.hearing_rounded,
    gradient: [Color(0xFF4F46E5), Color(0xFF7C3AED)],
  ),
  _TopicConfig(
    titleKey: 'vocabulary.topicTravel',
    tag: 'travel',
    subtitleKey: 'vocabulary.topicTravelSubtitle',
    icon: Icons.flight_takeoff_rounded,
    gradient: [Color(0xFFF97316), Color(0xFFFACC15)],
  ),
  _TopicConfig(
    titleKey: 'vocabulary.topicBusiness',
    tag: 'business',
    subtitleKey: 'vocabulary.topicBusinessSubtitle',
    icon: Icons.business_center_rounded,
    gradient: [Color(0xFF0F766E), Color(0xFF14B8A6)],
  ),
  _TopicConfig(
    titleKey: 'vocabulary.topicDailyLife',
    tag: 'daily',
    subtitleKey: 'vocabulary.topicDailyLifeSubtitle',
    icon: Icons.coffee_rounded,
    gradient: [Color(0xFF9333EA), Color(0xFFEC4899)],
  ),
  _TopicConfig(
    titleKey: 'vocabulary.topicScience',
    tag: 'science',
    subtitleKey: 'vocabulary.topicScienceSubtitle',
    icon: Icons.science_rounded,
    gradient: [Color(0xFF06B6D4), Color(0xFF3B82F6)],
  ),
  _TopicConfig(
    titleKey: 'vocabulary.topicTechnology',
    tag: 'technology',
    subtitleKey: 'vocabulary.topicTechnologySubtitle',
    icon: Icons.devices_rounded,
    gradient: [Color(0xFF475569), Color(0xFF1E293B)],
  ),
];
