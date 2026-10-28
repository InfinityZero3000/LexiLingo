import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/voice/duplex_voice_phase.dart';

/// Docked voice-conversation controls for the Lexi chat page. It owns no
/// state of its own beyond animation: everything shown comes from [phase].
class DuplexVoicePanel extends StatefulWidget {
  const DuplexVoicePanel({
    super.key,
    required this.phase,
    required this.level,
    required this.caption,
    required this.onEnd,
    required this.onOrbTap,
    this.onReplay,
  });

  final DuplexVoicePhase phase;
  final double level;
  final String caption;
  final VoidCallback onEnd;
  final VoidCallback onOrbTap;
  final VoidCallback? onReplay;

  @override
  State<DuplexVoicePanel> createState() => _DuplexVoicePanelState();
}

class _DuplexVoicePanelState extends State<DuplexVoicePanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(vsync: this);

  @override
  void didUpdateWidget(covariant DuplexVoicePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.phase != widget.phase) _syncLoop();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  void _syncLoop() {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final duration = switch (widget.phase) {
      DuplexVoicePhase.thinking => const Duration(milliseconds: 800),
      DuplexVoicePhase.speaking => const Duration(milliseconds: 600),
      _ => null,
    };
    if (duration == null || reduceMotion) {
      _loop
        ..stop()
        ..value = 0;
      return;
    }
    _loop.duration = duration;
    if (!_loop.isAnimating) _loop.repeat(reverse: true);
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  String get _status => switch (widget.phase) {
    DuplexVoicePhase.connecting => 'lexiChat.voice.statusConnecting'.tr(),
    DuplexVoicePhase.listening => 'lexiChat.voice.statusListening'.tr(),
    DuplexVoicePhase.hearing => 'lexiChat.voice.statusHearing'.tr(),
    DuplexVoicePhase.thinking => 'lexiChat.voice.statusThinking'.tr(),
    DuplexVoicePhase.speaking => 'lexiChat.voice.statusSpeaking'.tr(),
    _ => 'lexiChat.voice.errorGeneric'.tr(),
  };

  String get _orbLabel => switch (widget.phase) {
    DuplexVoicePhase.thinking ||
    DuplexVoicePhase.speaking => 'lexiChat.voice.a11yOrbInterrupt'.tr(),
    DuplexVoicePhase.error => 'lexiChat.voice.a11yOrbRetry'.tr(),
    _ => 'lexiChat.voice.a11yOrbListening'.tr(),
  };

  bool get _orbTappable =>
      widget.phase.canInterrupt || widget.phase == DuplexVoicePhase.error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              _status,
              style: theme.textTheme.titleSmall?.copyWith(
                color: widget.phase == DuplexVoicePhase.error
                    ? scheme.error
                    : scheme.onSurface,
              ),
            ),
          ),
          const SizedBox(height: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Text(
              widget.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _SideButton(
                icon: Icons.call_end_rounded,
                tooltip: 'lexiChat.voice.endSession'.tr(),
                background: scheme.errorContainer,
                foreground: scheme.onErrorContainer,
                onPressed: widget.onEnd,
              ),
              _buildOrb(scheme),
              _SideButton(
                icon: Icons.replay_rounded,
                tooltip: 'lexiChat.voice.replay'.tr(),
                background: scheme.secondaryContainer,
                foreground: scheme.onSecondaryContainer,
                onPressed: widget.onReplay,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOrb(ColorScheme scheme) {
    final phase = widget.phase;
    final (background, foreground, icon) = switch (phase) {
      DuplexVoicePhase.connecting => (
        scheme.surfaceContainerHighest,
        scheme.primary,
        null,
      ),
      DuplexVoicePhase.thinking => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
        Icons.more_horiz_rounded,
      ),
      DuplexVoicePhase.speaking => (
        scheme.tertiary,
        scheme.onTertiary,
        Icons.stop_rounded,
      ),
      DuplexVoicePhase.error => (
        scheme.errorContainer,
        scheme.onErrorContainer,
        Icons.refresh_rounded,
      ),
      _ => (scheme.primary, scheme.onPrimary, Icons.mic_rounded),
    };
    final listening =
        phase == DuplexVoicePhase.listening ||
        phase == DuplexVoicePhase.hearing;

    Widget orb = AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      width: 72,
      height: 72,
      decoration: BoxDecoration(shape: BoxShape.circle, color: background),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child: icon == null
            ? SizedBox(
                key: const ValueKey('spinner'),
                width: 28,
                height: 28,
                child: Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: foreground,
                  ),
                ),
              )
            : Icon(icon, key: ValueKey(icon), size: 32, color: foreground),
      ),
    );

    orb = AnimatedBuilder(
      animation: _loop,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_loop.value);
        return switch (phase) {
          DuplexVoicePhase.thinking => Opacity(
            opacity: 0.5 + 0.5 * t,
            child: child,
          ),
          DuplexVoicePhase.speaking => Transform.scale(
            scale: 1 + 0.08 * t,
            child: child,
          ),
          _ => child!,
        };
      },
      child: orb,
    );

    if (listening) {
      orb = TweenAnimationBuilder<double>(
        tween: Tween(end: 1 + 0.25 * widget.level.clamp(0.0, 1.0)),
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
        builder: (context, scale, child) =>
            Transform.scale(scale: scale, child: child),
        child: orb,
      );
    }

    return Semantics(
      button: _orbTappable,
      label: _orbLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: 96,
        height: 96,
        child: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _orbTappable ? widget.onOrbTap : null,
            child: orb,
          ),
        ),
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    required this.icon,
    required this.tooltip,
    required this.background,
    required this.foreground,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final Color background;
  final Color foreground;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        minimumSize: const Size(48, 48),
        backgroundColor: background,
        foregroundColor: foreground,
        disabledBackgroundColor: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        disabledForegroundColor: Theme.of(
          context,
        ).colorScheme.onSurface.withValues(alpha: 0.38),
      ),
    );
  }
}
