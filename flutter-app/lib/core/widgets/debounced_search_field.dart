import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_text_field.dart';

/// Search box that reports typing after a pause, not on every key.
class DebouncedSearchField extends StatefulWidget {
  const DebouncedSearchField({
    super.key,
    required this.onChanged,
    this.hint,
    this.initialValue = '',
    this.debounce = const Duration(milliseconds: 400),
  });

  final ValueChanged<String> onChanged;
  final String? hint;
  final String initialValue;
  final Duration debounce;

  @override
  State<DebouncedSearchField> createState() => _DebouncedSearchFieldState();
}

class _DebouncedSearchFieldState extends State<DebouncedSearchField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialValue,
  );
  Timer? _timer;
  String _last = '';

  @override
  void initState() {
    super.initState();
    _last = widget.initialValue.trim();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _emit(String value) {
    final query = value.trim();
    if (query == _last) return;
    _last = query;
    widget.onChanged(query);
  }

  void _onChanged(String value) {
    _timer?.cancel();
    _timer = Timer(widget.debounce, () => _emit(value));
    setState(() {});
  }

  void _clear() {
    _timer?.cancel();
    _controller.clear();
    _emit('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: _controller,
      hint: widget.hint ?? 'common.search'.tr(),
      prefixIcon: const Icon(Icons.search_rounded),
      textInputAction: TextInputAction.search,
      onChanged: _onChanged,
      onSubmitted: (value) {
        _timer?.cancel();
        _emit(value);
      },
      suffixIcon: _controller.text.isEmpty
          ? null
          : IconButton(
              constraints: const BoxConstraints(
                minWidth: kMinTapTarget,
                minHeight: kMinTapTarget,
              ),
              tooltip: 'common.clear'.tr(),
              icon: const Icon(Icons.close_rounded),
              onPressed: _clear,
            ),
    );
  }
}
