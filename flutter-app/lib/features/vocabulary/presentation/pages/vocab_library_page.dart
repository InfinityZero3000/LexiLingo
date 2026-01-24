import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocab_word.dart';
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
             child: const Icon(Icons.arrow_back_ios, color: AppColors.primary, size: 20),
          ),
        ),
        actions: [
          GestureDetector(
            onTap: () => _showAddWordDialog(context, vocabProvider),
            child: Container(
              margin: const EdgeInsets.only(right: 16),
              child: const Icon(Icons.add_circle, color: AppColors.primary, size: 28),
            ),
          )
        ],
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C2632) : Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)
                ],
              ),
              child: Row(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: Icon(Icons.search, color: AppColors.textGrey),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      decoration: const InputDecoration(
                        hintText: 'Search words...',
                        border: InputBorder.none,
                        hintStyle: TextStyle(color: AppColors.textGrey),
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
                Text('RECENT WORDS', style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, letterSpacing: 1.2, color: AppColors.textDark.withOpacity(0.6))),
              ],
            ),
          ),

          // List
          Expanded(
            child: words.isEmpty
                ? _buildDemoList(context)
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: words.length,
                    itemBuilder: (context, index) {
                      final word = words[index];
                      return _buildWordCard(
                        context,
                        word.word,
                        "/.../", // IPA missing in entity
                        word.definition, 
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, bool isSelected, {IconData? icon}) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isSelected ? AppColors.primary : (Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C2632) : Colors.white),
        borderRadius: BorderRadius.circular(18),
        border: isSelected ? null : Border.all(color: AppColors.primary.withOpacity(0.1)),
        boxShadow: [if(!isSelected) BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 2)]
      ),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 18, color: isSelected ? Colors.white : AppColors.primary),
            const SizedBox(width: 8),
          ],
          Text(label, style: TextStyle(
            color: isSelected ? Colors.white : (Theme.of(context).brightness == Brightness.dark ? Colors.white : AppColors.textDark),
            fontWeight: FontWeight.w600,
            fontSize: 14
          )),
        ],
      ),
    );
  }

  Widget _buildDemoList(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildWordCard(context, "Resilient", "/rɪˈzɪl.jənt/", "Able to recoil or spring back into shape after bending or being compressed."),
        const SizedBox(height: 12),
        _buildWordCard(context, "Departure", "/dɪˈpɑː.tʃər/", "The action of leaving, especially to start a journey."),
        const SizedBox(height: 12),
        _buildWordCard(context, "Ubiquitous", "/juːˈbɪk.wɪ.təs/", "Present, appearing, or found everywhere."),
        const SizedBox(height: 12),
        _buildWordCard(context, "Benevolent", "/bəˈnev.əl.ənt/", "Well meaning and kindly; marked by doing good."),
      ],
    );
  }

  Widget _buildWordCard(BuildContext context, String word, String ipa, String def) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
         color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1C2632) : Colors.white,
         borderRadius: BorderRadius.circular(12),
         boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))],
         border: Border.all(color: Colors.transparent),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 48, height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.menu_book, color: AppColors.primary),
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
                          Text(word, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(width: 8),
                          Text(ipa, style: TextStyle(color: AppColors.primary.withOpacity(0.7), fontSize: 12)),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(def, maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: AppColors.textGrey, fontSize: 14)
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.05),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.volume_up, color: AppColors.primary, size: 20),
          )
        ],
      ),
    );
  }

  void _showAddWordDialog(BuildContext context, VocabProvider provider) {
    // ... Existing implementation ...
    final wordController = TextEditingController();
    final defController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Word'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: wordController, decoration: const InputDecoration(labelText: 'Word')),
            TextField(controller: defController, decoration: const InputDecoration(labelText: 'Definition')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              if (wordController.text.isNotEmpty && defController.text.isNotEmpty) {
                provider.addWord(wordController.text, defController.text);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Save'),
          )
        ],
      ),
    );
  }
}

