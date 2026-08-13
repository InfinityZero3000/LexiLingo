import 'package:flutter/material.dart';
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
  bool _isSaving = false;
  String? _error;

  Future<void> _saveWord() async {
    if (_isSaving) return;

    setState(() {
      _isSaving = true;
      _error = null;
    });

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

      if (!mounted) return;
      Navigator.of(context).pop();

      final message = result.alreadyInCollection
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
          backgroundColor: AppColors.greenSuccess,
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

    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
    );
  }
}
