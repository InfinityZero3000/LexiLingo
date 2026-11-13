import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/story_selection_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart';

export 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart'
    show LexiMode;

/// The Lexi tab: free chat and topic conversations behind one mode switch.
///
/// Each mode is built on first visit and then kept under an IndexedStack, so
/// a half-typed message or a chosen level filter survives switching. The
/// switch lives in the chat page's own header row (and in a matching row
/// above the topic list) so the tab never stacks two headers. The chat page
/// is told when it is hidden so it releases its mic and speaker — two chat
/// backends, one tab.
class LexiHubPage extends StatefulWidget {
  final bool isActive;

  const LexiHubPage({super.key, this.isActive = true});

  @override
  State<LexiHubPage> createState() => _LexiHubPageState();
}

class _LexiHubPageState extends State<LexiHubPage> {
  LexiMode _mode = LexiMode.chat;
  final Set<LexiMode> _visited = {LexiMode.chat};

  void _select(LexiMode mode) {
    if (mode == _mode) return;
    setState(() {
      _visited.add(mode);
      _mode = mode;
    });
  }

  Widget _switch() => LexiModeSwitch(value: _mode, onChanged: _select);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: _mode.index,
          children: [
            for (final mode in LexiMode.values)
              if (!_visited.contains(mode))
                const SizedBox.shrink()
              else
                TickerMode(
                  enabled: widget.isActive && _mode == mode,
                  child: switch (mode) {
                    LexiMode.chat => LexiChatPage(
                      isActive: widget.isActive && _mode == mode,
                      titleSlot: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: _switch(),
                      ),
                    ),
                    LexiMode.topics => Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
                          child: _switch(),
                        ),
                        Expanded(
                          child: StorySelectionPage(
                            embedded: true,
                            onOpenFreeChat: () => _select(LexiMode.chat),
                          ),
                        ),
                      ],
                    ),
                  },
                ),
          ],
        ),
      ),
    );
  }
}
