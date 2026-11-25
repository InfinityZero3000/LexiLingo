import 'package:lexilingo_app/core/widgets/content_width.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/cefr_badge.dart';
import 'package:lexilingo_app/features/vocabulary/domain/entities/vocabulary_item_entity.dart';
import 'package:lexilingo_app/features/vocabulary/domain/repositories/vocabulary_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

/// Full-screen Word of the Day view.
/// Receives [VocabularyItemEntity] via Navigator arguments.
class WordOfDayScreen extends StatefulWidget {
  const WordOfDayScreen({super.key});

  @override
  State<WordOfDayScreen> createState() => _WordOfDayScreenState();
}

class _WordOfDayScreenState extends State<WordOfDayScreen> {
  bool _addedToCollection = false;

  @override
  Widget build(BuildContext context) {
    final word =
        ModalRoute.of(context)?.settings.arguments as VocabularyItemEntity?;
    if (word == null) {
      return Scaffold(
        body: Center(child: Text('vocabulary.noWordAvailable'.tr())),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final localizedTranslation = word.getTranslation(
      context.locale.languageCode,
    );
    final definitionTr = word.getDefinitionTranslation(
      context.locale.languageCode,
    );

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('vocabulary.wordOfTheDay'.tr()),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded),
            onPressed: () => _share(word),
          ),
        ],
      ),
      body: ContentWidth(
        maxWidth: ContentWidth.reading,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            20,
            AppSpacing.sm,
            20,
            AppSpacing.xxl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero word block
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.xl),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: AppColorRoles.primaryGradient(isDark),
                  ),
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: [
                    BoxShadow(
                      color: AppColorRoles.primary(
                        isDark,
                      ).withValues(alpha: 0.25),
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
                        CefrBadge(level: word.difficultyLevel, onColored: true),
                        const SizedBox(width: 8),
                        Text(
                          word.partOfSpeech,
                          style: Theme.of(context).textTheme.bodySmall!
                              .copyWith(
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
                        style: Theme.of(context).textTheme.bodyLarge!.copyWith(
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
                title: 'vocabulary.definition'.tr(),
                child: Text(
                  word.definition,
                  style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                    color: AppColorRoles.textPrimary(isDark),
                    height: 1.6,
                  ),
                ),
              ),

              // Translation in the user's app language (hidden when the word
              // has no entry for that locale).
              if (localizedTranslation != null || definitionTr != null) ...[
                const SizedBox(height: 16),
                _Section(
                  title: 'vocabulary.translationLabel'.tr(),
                  child: Text(
                    [
                      localizedTranslation,
                      definitionTr,
                    ].whereType<String>().join('\n'),
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
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
                  title: 'vocabulary.examples'.tr(),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: word.examples.map((example) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 4,
                              height: 4,
                              margin: const EdgeInsets.only(
                                top: AppSpacing.sm,
                                right: 10,
                              ),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColorRoles.primary(isDark),
                              ),
                            ),
                            Expanded(
                              child: Text(
                                '"$example"',
                                style: Theme.of(context).textTheme.bodyMedium!
                                    .copyWith(
                                      color: AppColorRoles.textSecondary(
                                        isDark,
                                      ),
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
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: AppColorRoles.primary(
                          isDark,
                        ).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(AppRadius.pill),
                      ),
                      child: Text(
                        '#$tag',
                        style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
                  onPressed: _addedToCollection
                      ? null
                      : () => _addToCollection(context, word),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.lg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.mdAll,
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
                        ? 'vocabulary.addedToFlashcardsShort'.tr()
                        : 'vocabulary.addToFlashcards'.tr(),
                    style: Theme.of(context).textTheme.bodyLarge!.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
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
    result.fold((_) {}, (_) {
      setState(() => _addedToCollection = true);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'vocabulary.addedToFlashcards'.tr(namedArgs: {'word': word.word}),
          ),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    });
  }

  void _share(VocabularyItemEntity word) {
    final details = [
      if (word.pronunciation != null) word.pronunciation!,
      word.definition,
    ].join('\n');
    final text = 'vocabulary.wordOfDayShare'.tr(
      namedArgs: {'word': word.word, 'details': details},
    );
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('common.copiedToClipboard'.tr()),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
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
          style: Theme.of(context).textTheme.labelSmall!.copyWith(
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
