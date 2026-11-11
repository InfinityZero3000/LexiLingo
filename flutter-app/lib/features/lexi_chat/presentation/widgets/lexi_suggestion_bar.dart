import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/lexi_chat/data/lexi_reply_suggester.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/entities/lexi_message.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/lexi_followups.dart';

/// Tap-to-send chips under Lexi's latest message: answers to her question
/// (fetched, so they appear a beat late) then follow-ups that fit what she said.
class LexiSuggestionBar extends StatefulWidget {
  final LexiMessage message;
  final String nativeLanguage;
  final bool isDark;
  final ValueChanged<String> onSend;

  const LexiSuggestionBar({
    super.key,
    required this.message,
    required this.nativeLanguage,
    required this.isDark,
    required this.onSend,
  });

  @override
  State<LexiSuggestionBar> createState() => _LexiSuggestionBarState();
}

class _LexiSuggestionBarState extends State<LexiSuggestionBar> {
  List<String> _options = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(LexiSuggestionBar old) {
    super.didUpdateWidget(old);
    if (old.message.id != widget.message.id) {
      _options = const [];
      _load();
    }
  }

  Future<void> _load() async {
    final message = widget.message;
    if (!endsWithQuestion(message.content) ||
        !sl.isRegistered<LexiReplySuggester>()) {
      return;
    }
    final options = await sl<LexiReplySuggester>().suggest(message.content);
    // A newer message may have replaced this one while the request ran.
    if (mounted && widget.message.id == message.id) {
      setState(() => _options = options);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = widget.isDark;
    final followups = lexiFollowups(
      widget.message,
      nativeLanguage: widget.nativeLanguage,
    );
    final primary = AppColorRoles.primary(isDark);

    Widget chip(String label, VoidCallback onTap, {bool answer = false}) {
      return ActionChip(
        avatar: answer
            ? Icon(Icons.reply_rounded, size: 14, color: primary)
            : null,
        label: Text(label, overflow: TextOverflow.ellipsis),
        onPressed: onTap,
        labelStyle: TextStyle(
          fontSize: 12,
          color: answer ? primary : AppColorRoles.textSecondary(isDark),
        ),
        side: BorderSide(
          color: answer
              ? primary.withValues(alpha: 0.5)
              : (isDark ? AppColors.surfaceDarkChat : AppColors.chatBgLight),
        ),
        backgroundColor: isDark
            ? AppColors.surfaceDarkInk
            : AppColors.backgroundLight,
      );
    }

    final chips = <Widget>[
      for (final o in _options) chip(o, () => widget.onSend(o), answer: true),
      for (final f in followups)
        chip(f.i18nKey.tr(), () => widget.onSend(f.prompt)),
    ];

    return SizedBox(
      height: 40,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (_, i) => chips[i],
      ),
    );
  }
}
