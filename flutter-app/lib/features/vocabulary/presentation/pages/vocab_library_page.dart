import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/vocab_word_detail_sheet.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class VocabLibraryPage extends StatefulWidget {
  const VocabLibraryPage({super.key});

  @override
  State<VocabLibraryPage> createState() => _VocabLibraryPageState();
}

class _VocabLibraryPageState extends State<VocabLibraryPage> {
  final TextEditingController _searchController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final vocabProvider = Provider.of<VocabProvider>(context);
    List<VocabWord> words = vocabProvider.words;

    // Hardcoded demo data if empty to match design request
    if (words.isEmpty) {
      // We can't actually modify the provider from here during build without side effects.
      // We will just render a demo list instead.
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vocabulary Library'),
        centerTitle: true,
        leading: GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Container(
            margin: const EdgeInsets.all(8),
            decoration: BoxDecoration(
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
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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
                    child: Icon(Icons.search, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search words...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                _buildFilterChip('All', true),
                const SizedBox(width: 8),
                _buildFilterChip('Travel', false, icon: Icons.flight),
                const SizedBox(width: 8),
                _buildFilterChip('Business', false, icon: Icons.work),
                const SizedBox(width: 8),
                _buildFilterChip('Daily', false, icon: Icons.coffee),
              ],
            ),
          ),

          // "Recent Words" Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  'RECENT WORDS',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
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
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, {IconData? icon}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: isSelected
            ? null
            : Border.all(color: AppColors.primary.withValues(alpha: 0.1)),
        boxShadow: [
          if (!isSelected)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 2,
            ),
        ],
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 18,
              color: isSelected ? Colors.white : AppColors.primary,
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: isSelected
                  ? colorScheme.onPrimary
                  : colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildDemoList(BuildContext context) {
    final demoWords = [
      VocabWord(word: 'Resilient', definition: 'Able to recoil or spring back into shape after bending or being compressed.', pronunciation: '/rɪˈzɪl.jənt/'),
      VocabWord(word: 'Departure', definition: 'The action of leaving, especially to start a journey.', pronunciation: '/dɪˈpɑː.tʃər/'),
      VocabWord(word: 'Ubiquitous', definition: 'Present, appearing, or found everywhere.', pronunciation: '/juːˈbɪk.wɪ.təs/'),
      VocabWord(word: 'Benevolent', definition: 'Well meaning and kindly; marked by doing good.', pronunciation: '/bəˈnev.əl.ənt/'),
    ];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final w in demoWords) ...[
          _buildWordCard(context, w),
          const SizedBox(height: 12),
        ],
      ],
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
                        child: Icon(Icons.menu_book, color: colorScheme.primary),
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
                                      color: AppColors.primary.withValues(alpha: 0.7),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              def,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.onSurfaceVariant,
                                fontSize: 14,
                              ),
                            ),
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
      example: _exampleController.text.trim().isEmpty ? null : _exampleController.text.trim(),
      partOfSpeech: _partOfSpeech,
    );
    if (!mounted) return;
    setState(() => _saving = false);

    if (ok) {
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.provider.errorMessage ?? 'Failed to save word'),
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
            'Add New Word',
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
              labelText: 'Word',
              hintText: 'e.g. resilient',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              labelText: 'Definition',
              hintText: 'What does this word mean?',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
              labelText: 'Example sentence (optional)',
              hintText: 'e.g. She was resilient in the face of adversity.',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                  child: const Text('Cancel'),
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
                      : const Text(
                          'Save Word',
                          style: TextStyle(
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
        message: 'Word not found in dictionary',
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
  const _InfoChip({required this.icon, required this.label, required this.color});

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
