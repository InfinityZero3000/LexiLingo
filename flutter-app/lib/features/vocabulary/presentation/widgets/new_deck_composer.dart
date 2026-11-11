import 'dart:math';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';
import 'package:lexilingo_app/features/vocabulary/presentation/providers/vocab_provider.dart';
import 'package:provider/provider.dart';

const _deckPalette = [
  '#2196F3',
  '#4CAF50',
  '#FF9800',
  '#E91E63',
  '#9C27B0',
  '#009688',
  '#F44336',
  '#3F51B5',
  '#795548',
  '#00897B',
  '#D81B60',
  '#5E35B1',
];

/// Inline "name + random colour" row that creates a collection and reports it back.
class NewDeckComposer extends StatefulWidget {
  final ValueChanged<VocabularyDeck> onCreated;
  final VoidCallback onCancel;

  const NewDeckComposer({
    super.key,
    required this.onCreated,
    required this.onCancel,
  });

  @override
  State<NewDeckComposer> createState() => _NewDeckComposerState();
}

class _NewDeckComposerState extends State<NewDeckComposer> {
  final _random = Random();
  final _nameController = TextEditingController();
  late String _color = _randomColor();
  bool _isCreating = false;
  String? _error;

  String _randomColor() => _deckPalette[_random.nextInt(_deckPalette.length)];

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty || _isCreating) return;
    setState(() {
      _isCreating = true;
      _error = null;
    });
    final deck = await context.read<VocabProvider>().createDeckRecord(
      name,
      null,
      _color,
    );
    if (!mounted) return;
    if (deck == null) {
      setState(() {
        _isCreating = false;
        _error = 'vocabulary.createDeckFailed'.tr();
      });
      return;
    }
    widget.onCreated(deck);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Tooltip(
          message: 'vocabulary.rerollColor'.tr(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: () => setState(() => _color = _randomColor()),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: deckGradient(deckColorFromHex(_color)),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.shuffle, color: Colors.white, size: 20),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: TextField(
            controller: _nameController,
            autofocus: true,
            maxLength: 100,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _create(),
            decoration: InputDecoration(
              hintText: 'vocabulary.collectionNameHint'.tr(),
              errorText: _error,
              counterText: '',
              isDense: true,
            ),
          ),
        ),
        IconButton(
          onPressed: _isCreating ? null : _create,
          icon: _isCreating
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: LottieLoadingWidget.tiny(),
                )
              : const Icon(Icons.check),
        ),
        IconButton(
          onPressed: _isCreating ? null : widget.onCancel,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}
