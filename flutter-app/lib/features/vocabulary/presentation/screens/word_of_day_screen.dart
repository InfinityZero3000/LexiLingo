import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';

/// Full-screen Word of the Day view.
/// Receives [VocabularyItemEntity] via Navigator arguments.
class WordOfDayScreen extends StatefulWidget {
  const WordOfDayScreen({super.key});

  @override
  State<WordOfDayScreen> createState() => _WordOfDayScreenState();
}

class _WordOfDayScreenState extends State<WordOfDayScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _fade;
  late final Animation<Offset> _slide;
  bool _addedToCollection = false;

  @override
  void initState() {
    super.initState();
    _entrance = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _entrance, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.08),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _entrance, curve: Curves.easeOutCubic));
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final word = ModalRoute.of(context)?.settings.arguments as VocabularyItemEntity?;
    if (word == null) {
      return const Scaffold(
        body: Center(child: Text('No word available')),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cefrColor = CefrBadge.colorForLevel(word.difficultyLevel);

    return Scaffold(
      backgroundColor: isDark ? AppColors.backgroundDark : AppColors.backgroundLight,
      appBar: AppBar(
        title: const Text('Word of the Day'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _share(word),
          ),
        ],
      ),
      body: FadeTransition(
        opacity: _fade,
        child: SlideTransition(
          position: _slide,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero word block
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: AppColorRoles.primaryGradient(isDark),
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: cefrColor.withValues(alpha: 0.25),
                        blurRadius: 20,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          CefrBadge(level: word.difficultyLevel),
                          const SizedBox(width: 8),
                          Text(
                            word.partOfSpeech,
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.8),
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        word.word,
                        style: const TextStyle(
                          fontSize: 40,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        ),
                      ),
                      if (word.pronunciation != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          word.pronunciation!,
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.white.withValues(alpha: 0.8),
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Definition
                _Section(
                  title: 'Definition',
                  child: Text(
                    word.definition,
                    style: TextStyle(
                      fontSize: 15,
                      color: AppColorRoles.textPrimary(isDark),
                      height: 1.6,
                    ),
                  ),
                ),

                // Vietnamese translation
                if (word.vietnameseTranslation != null) ...[
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Vietnamese',
                    child: Text(
                      word.vietnameseTranslation!,
                      style: TextStyle(
                        fontSize: 15,
                        color: AppColorRoles.textPrimary(isDark),
                        height: 1.5,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],

                // Example sentences
                if (word.examples.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _Section(
                    title: 'Examples',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: word.examples.map((example) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 4,
                                height: 4,
                                margin: const EdgeInsets.only(top: 8, right: 10),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: AppColorRoles.primary(isDark),
                                ),
                              ),
                              Expanded(
                                child: Text(
                                  '"$example"',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: AppColorRoles.textSecondary(isDark),
                                    height: 1.5,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],

                // Tags
                if (word.tags != null && word.tags!.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: word.tags!.map((tag) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: AppColorRoles.primary(isDark).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '#$tag',
                          style: TextStyle(
                            fontSize: 11,
                            color: AppColorRoles.primary(isDark),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],

                const SizedBox(height: 32),

                // Add to flashcards button
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _addedToCollection ? null : () => _addToCollection(context, word),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    icon: Icon(
                      _addedToCollection
                          ? Icons.check_circle_rounded
                          : Icons.bookmark_add_rounded,
                      size: 20,
                    ),
                    label: Text(
                      _addedToCollection
                          ? 'Added to Flashcards!'
                          : 'Add to Flashcards',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addToCollection(
    BuildContext context,
    VocabularyItemEntity word,
  ) async {
    HapticFeedback.lightImpact();
    final repo = sl<VocabularyRepository>();
    final result = await repo.addToCollection(word.id);
    if (!mounted) return;
    result.fold(
      (_) {},
      (_) {
        setState(() => _addedToCollection = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('"${word.word}" added to your flashcards!'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      },
    );
  }

  void _share(VocabularyItemEntity word) {
    final text = 'Word of the Day: "${word.word}"\n'
        '${word.pronunciation != null ? '${word.pronunciation}\n' : ''}'
        '${word.definition}\n\n'
        'Learn English with LexiLingo!';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Copied to clipboard!'),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;
  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppColorRoles.textMuted(isDark),
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
