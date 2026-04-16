import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/quick_save_word_sheet.dart';

/// Adds a "Save Word" item to text selection context menu.
class QuickSaveSelectionArea extends StatefulWidget {
  final Widget child;
  final String sourceType;
  final String? sourceReference;
  final String? contextSentence;
  final bool requireSingleWord;

  const QuickSaveSelectionArea({
    super.key,
    required this.child,
    required this.sourceType,
    this.sourceReference,
    this.contextSentence,
    this.requireSingleWord = true,
  });

  @override
  State<QuickSaveSelectionArea> createState() => _QuickSaveSelectionAreaState();
}

class _QuickSaveSelectionAreaState extends State<QuickSaveSelectionArea> {
  String _selectedText = '';

  @override
  Widget build(BuildContext context) {
    final hostContext = context;

    return SelectionArea(
      onSelectionChanged: (selectedContent) {
        _selectedText = selectedContent?.plainText ?? '';
      },
      contextMenuBuilder: (context, selectableRegionState) {
        final buttonItems = List<ContextMenuButtonItem>.from(
          selectableRegionState.contextMenuButtonItems,
        );

        buttonItems.add(
          ContextMenuButtonItem(
            label: 'Save Word',
            onPressed: () {
              final word = _extractCandidateWord(
                _selectedText,
                requireSingleWord: widget.requireSingleWord,
              );

              ContextMenuController.removeAny();

              if (word == null) {
                final messenger = ScaffoldMessenger.maybeOf(hostContext);
                messenger?.showSnackBar(
                  const SnackBar(
                    content: Text('Please select exactly one word to save.'),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: AppColors.orange,
                  ),
                );
                return;
              }

              showQuickSaveWordSheet(
                hostContext,
                word: word,
                sourceType: widget.sourceType,
                sourceReference: widget.sourceReference,
                contextSentence: widget.contextSentence,
              );
            },
          ),
        );

        return AdaptiveTextSelectionToolbar.buttonItems(
          anchors: selectableRegionState.contextMenuAnchors,
          buttonItems: buttonItems,
        );
      },
      child: widget.child,
    );
  }

  String? _extractCandidateWord(
    String selectedText, {
    required bool requireSingleWord,
  }) {
    final collapsed = selectedText.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (collapsed.isEmpty) return null;

    if (requireSingleWord && collapsed.contains(' ')) {
      return null;
    }

    final candidate = requireSingleWord ? collapsed : collapsed.split(' ').first;
    final cleaned = candidate
        .replaceAll(RegExp(r"^[^A-Za-z0-9']+"), '')
        .replaceAll(RegExp(r"[^A-Za-z0-9']+$"), '')
        .toLowerCase();

    if (cleaned.isEmpty) return null;
    return cleaned;
  }
}
