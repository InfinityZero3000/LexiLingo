import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/widgets/new_deck_composer.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/services/quick_save_vocabulary_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:easy_localization/easy_localization.dart';

Future<void> showQuickSaveWordSheet(
  BuildContext context, {
  required String word,
  required String sourceType,
  String? sourceReference,
  String? contextSentence,
  String? definition,
  String? translation,
  String? partOfSpeech,
}) async {
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _QuickSaveWordSheet(
      hostContext: context,
      word: word,
      sourceType: sourceType,
      sourceReference: sourceReference,
      contextSentence: contextSentence,
      definition: definition,
      translation: translation,
      partOfSpeech: partOfSpeech,
    ),
  );
}

class _QuickSaveWordSheet extends StatefulWidget {
  final BuildContext hostContext;
  final String word;
  final String sourceType;
  final String? sourceReference;
  final String? contextSentence;
  final String? definition;
  final String? translation;
  final String? partOfSpeech;

  const _QuickSaveWordSheet({
    required this.hostContext,
    required this.word,
    required this.sourceType,
    this.sourceReference,
    this.contextSentence,
    this.definition,
    this.translation,
    this.partOfSpeech,
  });

  @override
  State<_QuickSaveWordSheet> createState() => _QuickSaveWordSheetState();
}

class _QuickSaveWordSheetState extends State<_QuickSaveWordSheet> {
  final _selectedDeckIds = <String>{};
  bool _isSaving = false;
  bool _isCreating = false;
  String? _error;

  Future<void> _saveWord() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

    final vocab = context.read<VocabProvider>();
    try {
      final service = sl<QuickSaveVocabularyService>();
      final result = await service.quickSaveWord(
        word: widget.word,
        sourceType: widget.sourceType,
        sourceReference: widget.sourceReference,
        contextSentence: widget.contextSentence,
        definition: widget.definition,
        translation: widget.translation,
        partOfSpeech: widget.partOfSpeech,
      );

      var addedToDecks = 0;
      final userVocabId = result.userVocabularyId;
      if (userVocabId != null) {
        for (final deckId in _selectedDeckIds) {
          if (await vocab.addWordToDeck(deckId, userVocabId)) addedToDecks++;
        }
      }
      final deckFailed = addedToDecks < _selectedDeckIds.length;

      if (!mounted) return;
      Navigator.of(context).pop();

      final message = deckFailed
          ? 'vocabulary.addToDeckFailed'.tr()
          : addedToDecks > 0
          ? 'vocabulary.savedToCollections'.tr(
              args: [result.normalizedWord, '$addedToDecks'],
            )
          : result.alreadyInCollection
          ? '"${result.normalizedWord}" is already in your vocabulary.'
          : result.createdNewItem
          ? 'Saved new word "${result.normalizedWord}" to vocabulary.'
          : 'Saved "${result.normalizedWord}" to vocabulary.';

      if (!widget.hostContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(widget.hostContext);
      messenger?.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: deckFailed
              ? AppColors.errorBright
              : AppColors.greenSuccess,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _error = 'Could not save this word. Please try again.';
      });

      if (!widget.hostContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(widget.hostContext);
      messenger?.showSnackBar(
        SnackBar(
          content: Text('vocabulary.saveWordFailed'.tr()),
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.errorBright,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final decks = context.watch<VocabProvider>().decks;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        decoration: BoxDecoration(
          color: isDark ? AppColors.surfaceDark : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white24 : AppColors.grey300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'vocabulary.saveToVocabulary'.tr(),
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: isDark ? Colors.white : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? AppColors.surfaceDarkChat
                      : AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  widget.word,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'vocabulary.collectionPickerTitle'.tr(),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : AppColors.textDark,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final deck in decks)
                    FilterChip(
                      avatar: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          gradient: deckGradient(deckColorFromHex(deck.color)),
                          shape: BoxShape.circle,
                        ),
                      ),
                      label: Text(deck.name),
                      selected: _selectedDeckIds.contains(deck.id),
                      selectedColor: deckColorFromHex(
                        deck.color,
                      ).withValues(alpha: 0.2),
                      onSelected: _isSaving
                          ? null
                          : (on) => setState(
                              () => on
                                  ? _selectedDeckIds.add(deck.id)
                                  : _selectedDeckIds.remove(deck.id),
                            ),
                    ),
                  if (!_isCreating)
                    ActionChip(
                      avatar: const Icon(Icons.add, size: 18),
                      label: Text('vocabulary.newCollection'.tr()),
                      onPressed: _isSaving
                          ? null
                          : () => setState(() => _isCreating = true),
                    ),
                ],
              ),
              if (_isCreating) ...[
                const SizedBox(height: 8),
                NewDeckComposer(
                  onCreated: (deck) => setState(() {
                    _selectedDeckIds.add(deck.id);
                    _isCreating = false;
                  }),
                  onCancel: () => setState(() => _isCreating = false),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: AppColors.errorBright,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSaving
                          ? null
                          : () => Navigator.of(context).pop(),
                      child: Text('common.cancel'.tr()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: _isSaving ? null : _saveWord,
                      child: _isSaving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: LottieLoadingWidget.tiny(),
                            )
                          : Text('vocabulary.saveWord'.tr()),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
