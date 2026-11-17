import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/chat/presentation/pages/story_selection_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/pages/lexi_chat_page.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

export 'package:lexilingo_app/features/lexi_chat/presentation/widgets/lexi_mode_switch.dart'
    show LexiMode;

/// The Lexi tab: free chat and topic conversations behind one mode switch.
///
/// Each mode is built on first visit and then kept alive, so a half-typed
/// message or a chosen level filter survives switching. The switch lives in
/// the chat page's own header row and in a matching full-width row above the
/// topic list, so the tab never stacks two headers.
///
/// Switching is one animation with three parts, all compositor-only:
/// - the chat pane never moves or fades — it is opaque and stays put;
/// - the topics pane fades and slides over it (one opacity layer, not two);
/// - a single overlay switch morphs between the two slots' rects, so the
///   narrow header switch grows into the wide one instead of jumping.
/// The overlay exists only while animating; at rest each pane shows its own
/// inline switch, so the chat drawer and resizes never fight a floating copy.
class LexiHubPage extends StatefulWidget {
  final bool isActive;

  const LexiHubPage({super.key, this.isActive = true});

  @override
  State<LexiHubPage> createState() => _LexiHubPageState();
}

class _LexiHubPageState extends State<LexiHubPage>
    with SingleTickerProviderStateMixin {
  static const _slide = 24.0;

  LexiMode _mode = LexiMode.chat;
  final Set<LexiMode> _visited = {LexiMode.chat};
  final _modeN = ValueNotifier(LexiMode.chat);
  final _morphing = ValueNotifier(false);

  final _slotKeys = {for (final m in LexiMode.values) m: GlobalKey()};
  final _paneKeys = {for (final m in LexiMode.values) m: GlobalKey()};
  final Map<LexiMode, Rect> _slotRects = {};

  // Cached so a morph start/end does not hand the chat page a new widget.
  late final Map<LexiMode, Widget> _slots = {
    for (final m in LexiMode.values) m: _buildSlot(m),
  };

  /// 0 = free chat fully shown, 1 = topics fully shown.
  late final AnimationController _transition = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );
  // Symmetric: easeOutCubic spent ~80% of the distance in the first third of
  // the time, which read as an instant jump.
  late final CurvedAnimation _curve = CurvedAnimation(
    parent: _transition,
    curve: Curves.easeInOutCubic,
  );

  @override
  void dispose() {
    _curve.dispose();
    _transition.dispose();
    _modeN.dispose();
    _morphing.dispose();
    super.dispose();
  }

  void _select(LexiMode mode) {
    if (mode == _mode) return;
    _visited.add(mode);
    setState(() => _mode = mode);
    _modeN.value = mode;
    final target = mode == LexiMode.topics ? 1.0 : 0.0;
    if (MediaQuery.disableAnimationsOf(context)) {
      _transition.value = target;
      return;
    }
    // The setState above rebuilds the chat page (and builds the topic page on
    // a first visit). Start on the next frame so that cost is not paid inside
    // the animation, and so both slots are laid out and can be measured.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _mode != mode) return;
      _morphing.value = _measureSlots();
      _transition.animateTo(target).whenCompleteOrCancel(() {
        if (mounted && !_transition.isAnimating) _morphing.value = false;
      });
    });
  }

  /// Slot rects in pane coordinates — measured against the pane, not the
  /// screen, so the topics pane's slide offset does not leak in.
  bool _measureSlots() {
    for (final mode in LexiMode.values) {
      final slot = _slotKeys[mode]!.currentContext?.findRenderObject();
      final pane = _paneKeys[mode]!.currentContext?.findRenderObject();
      if (slot is! RenderBox || pane is! RenderBox || !slot.hasSize) {
        return false;
      }
      _slotRects[mode] =
          slot.localToGlobal(Offset.zero, ancestor: pane) & slot.size;
    }
    return true;
  }

  Widget _buildSlot(LexiMode mode) => KeyedSubtree(
    key: _slotKeys[mode],
    child: ListenableBuilder(
      listenable: Listenable.merge([_modeN, _morphing]),
      builder: (context, _) => Visibility(
        visible: !_morphing.value,
        maintainSize: true,
        maintainAnimation: true,
        maintainState: true,
        child: LexiModeSwitch(value: _modeN.value, onChanged: _select),
      ),
    ),
  );

  Widget _morphingSwitch() {
    return ListenableBuilder(
      listenable: Listenable.merge([_curve, _morphing, _modeN]),
      builder: (context, _) {
        final from = _slotRects[LexiMode.chat];
        final to = _slotRects[LexiMode.topics];
        final active = _morphing.value && from != null && to != null;
        final rect = active
            ? Rect.lerp(from, to, _curve.value)!
            : const Rect.fromLTWH(0, 0, 200, LexiModeSwitch.height);
        double reveal(Rect r) =>
            r.width - 6 >= LexiModeSwitch.labelMinWidth ? 1 : 0;
        // Labels wait until the frame has opened a little, so text is never
        // squeezed into a half-grown pill.
        final labelT = Curves.easeInOut.transform(
          ((_curve.value - 0.3) / 0.7).clamp(0.0, 1.0),
        );
        return Positioned.fromRect(
          rect: rect,
          // Kept mounted so its thumb slides on a mode change like the
          // inline ones; offstage costs no paint at rest.
          child: Offstage(
            offstage: !active,
            child: RepaintBoundary(
              child: LexiModeSwitch(
                value: _modeN.value,
                onChanged: _select,
                labelReveal: active
                    ? reveal(from) + (reveal(to) - reveal(from)) * labelT
                    : 0,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pane(LexiMode mode, Widget child) {
    final slides = mode == LexiMode.topics;
    return AnimatedBuilder(
      animation: _curve,
      child: RepaintBoundary(key: _paneKeys[mode], child: child),
      builder: (context, child) {
        final t = _curve.value;
        // Chat is only covered, never faded: hidden once topics is opaque.
        final hidden = slides ? t == 0 : t == 1;
        Widget pane = child!;
        if (slides && t < 1) {
          pane = Opacity(
            opacity: t,
            child: Transform.translate(
              offset: Offset(_slide * (1 - t), 0),
              child: pane,
            ),
          );
        }
        return Offstage(
          offstage: hidden,
          child: TickerMode(
            enabled: widget.isActive && !hidden && _mode == mode,
            child: pane,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      body: SafeArea(
        bottom: false,
        child: AnimatedBuilder(
          animation: _transition,
          builder: (context, child) =>
              IgnorePointer(ignoring: _transition.isAnimating, child: child),
          child: Stack(
            fit: StackFit.expand,
            children: [
              for (final mode in LexiMode.values)
                if (_visited.contains(mode))
                  _pane(mode, switch (mode) {
                    LexiMode.chat => LexiChatPage(
                      isActive: widget.isActive && _mode == mode,
                      titleSlot: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.xs,
                        ),
                        child: _slots[mode],
                      ),
                    ),
                    LexiMode.topics => Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            6,
                            AppSpacing.lg,
                            6,
                          ),
                          child: _slots[mode],
                        ),
                        Expanded(
                          child: StorySelectionPage(
                            embedded: true,
                            onOpenFreeChat: () => _select(LexiMode.chat),
                          ),
                        ),
                      ],
                    ),
                  }),
              _morphingSwitch(),
            ],
          ),
        ),
      ),
    );
  }
}
