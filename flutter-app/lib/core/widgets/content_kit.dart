import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'app_back_button.dart';

/// Page and hero titles: the theme's own face (Lexend), only heavier and larger.
TextStyle contentDisplay(
  BuildContext context, {
  double size = 24,
  Color? color,
}) => Theme.of(context).textTheme.titleLarge!.copyWith(
  fontSize: size,
  fontWeight: FontWeight.w700,
  height: 1.2,
  color: color ?? Theme.of(context).colorScheme.onSurface,
);

/// Secondary text: 0.7 of onSurface stays above 4.5:1 on both page grounds.
Color contentMuted(BuildContext context) =>
    Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7);

Duration _motion(BuildContext context, int ms) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: ms);

/// Remote artwork that fades in and falls back to a primary-tinted block.
class ContentImage extends StatelessWidget {
  const ContentImage({
    super.key,
    required this.url,
    this.fallbackIcon = PhosphorIconsBold.headphones,
  });

  final String url;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fallback = ColoredBox(
      color: primary.withValues(alpha: 0.14),
      child: Center(child: Icon(fallbackIcon, color: primary, size: 32)),
    );
    if (url.isEmpty) return fallback;
    return Image.network(
      url,
      fit: BoxFit.cover,
      webHtmlElementStrategy: WebHtmlElementStrategy.never,
      errorBuilder: (_, _, _) => fallback,
      frameBuilder: (context, child, frame, sync) => sync
          ? child
          : AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: _motion(context, 300),
              curve: Curves.easeOut,
              child: child,
            ),
    );
  }
}

/// A blurred copy of [url] under a dark scrim, to sit behind white text.
///
/// The scrim is black regardless of theme so white text holds contrast on any
/// artwork; [fallback] is drawn instead when there is no [url].
class ContentBackdrop extends StatelessWidget {
  const ContentBackdrop({super.key, required this.url, this.fallback});

  final String url;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    // Clipped here, not left to callers: the blurred copy is scaled up past its
    // own bounds and would otherwise smear over whatever sits next to it.
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              // Scaled up so the blur does not fade out at the edges.
              child: Transform.scale(
                scale: 1.3,
                child: url.isEmpty && fallback != null
                    ? fallback
                    : ContentImage(url: url),
              ),
            ),
          ),
          const ColoredBox(color: Color(0x99000000)),
        ],
      ),
    );
  }
}

/// Back bar for a page whose header is artwork: clear and white over the
/// artwork, solid with the page title once [collapsed]. Place it inside a
/// [Stack] above the scroll view.
class ContentTopBar extends StatelessWidget {
  const ContentTopBar({
    super.key,
    required this.title,
    required this.collapsed,
    this.actionsBuilder,
  });

  final String title;
  final bool collapsed;

  /// Trailing widgets, given the icon colour that suits the current state.
  final List<Widget> Function(Color iconColor)? actionsBuilder;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final iconColor = collapsed ? scheme.onSurface : Colors.white;
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: AnimatedContainer(
        duration: _motion(context, 200),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: collapsed ? scheme.surface : Colors.transparent,
          border: Border(
            bottom: BorderSide(
              color: collapsed ? scheme.outlineVariant : Colors.transparent,
            ),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                const SizedBox(width: 8),
                AppBackButton(color: iconColor),
                Expanded(
                  child: AnimatedOpacity(
                    duration: _motion(context, 200),
                    opacity: collapsed ? 1 : 0,
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                ...?actionsBuilder?.call(iconColor),
                const SizedBox(width: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary pill drawn inside a tappable surface; it has no gesture of its own.
class ContentCta extends StatelessWidget {
  const ContentCta({super.key, required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(24),
      ),
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18, color: scheme.onPrimary),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: scheme.onPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-bleed artwork under a dark scrim with a bold title and a call to action.
///
/// The scrim is black regardless of theme: white text has to hold contrast on
/// whatever image the backend sends.
class ContentHero extends StatelessWidget {
  const ContentHero({
    super.key,
    required this.imageUrl,
    required this.title,
    required this.cta,
    required this.onTap,
    this.eyebrow,
    this.subtitle,
  });

  final String imageUrl;
  final String title;
  final Widget cta;
  final VoidCallback onTap;
  final String? eyebrow;
  final String? subtitle;

  static const height = 240.0;

  /// Grows with the text scale so a 2-line title and subtitle never clip.
  static double heightOf(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    return height + 140 * (scale - 1).clamp(0.0, 1.0);
  }

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(
        button: true,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: SizedBox(
            height: heightOf(context),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ExcludeSemantics(child: ContentImage(url: imageUrl)),
                const DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.2, 1],
                      colors: [Color(0x00000000), Color(0xD9000000)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (eyebrow != null) ...[
                        Text(
                          eyebrow!.toUpperCase(),
                          style: const TextStyle(
                            color: Color(0xCCFFFFFF),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 1.6,
                          ),
                        ),
                        const SizedBox(height: 8),
                      ],
                      Text(
                        title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: contentDisplay(context, color: Colors.white),
                      ),
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xE6FFFFFF),
                            fontSize: 14,
                            height: 1.4,
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      cta,
                    ],
                  ),
                ),
                Positioned.fill(
                  child: Material(
                    type: MaterialType.transparency,
                    child: InkWell(onTap: onTap),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Page dots under a hero carousel; the active dot stretches into a pill.
class ContentDots extends StatelessWidget {
  const ContentDots({super.key, required this.count, required this.index});

  final int count;
  final int index;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ExcludeSemantics(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < count; i++)
            AnimatedContainer(
              duration: _motion(context, 250),
              curve: Curves.easeOut,
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == index ? 20 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == index
                    ? scheme.primary
                    : scheme.onSurface.withValues(alpha: 0.25),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
        ],
      ),
    );
  }
}

/// Peeking page carousel with dots that moves on by itself.
///
/// A learner's own swipe pushes the next move back by a full [autoAdvance];
/// it stays still for a single page, under reduced motion, and while its
/// route is covered (a covered route has no tickers, so animateToPage would
/// never finish).
class ContentCarousel extends StatefulWidget {
  const ContentCarousel({
    super.key,
    required this.count,
    required this.height,
    required this.itemBuilder,
    this.autoAdvance = const Duration(seconds: 5),
  });

  final int count;
  final double height;
  final IndexedWidgetBuilder itemBuilder;
  final Duration autoAdvance;

  @override
  State<ContentCarousel> createState() => _ContentCarouselState();
}

class _ContentCarouselState extends State<ContentCarousel> {
  final _controller = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _schedule();
  }

  @override
  void didUpdateWidget(ContentCarousel old) {
    super.didUpdateWidget(old);
    if (old.count != widget.count) _schedule();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _schedule() {
    _timer?.cancel();
    if (widget.count < 2) return;
    _timer = Timer.periodic(widget.autoAdvance, (_) => _advance());
  }

  void _advance() {
    if (!mounted ||
        !_controller.hasClients ||
        !TickerMode.of(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    _controller.animateToPage(
      (_index + 1) % widget.count,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeInOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0) return const SizedBox.shrink();
    final index = _index.clamp(0, widget.count - 1);

    return Column(
      children: [
        SizedBox(
          height: widget.height,
          child: NotificationListener<ScrollStartNotification>(
            onNotification: (n) {
              if (n.dragDetails != null) _schedule();
              return false;
            },
            child: PageView.builder(
              controller: _controller,
              itemCount: widget.count,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: widget.itemBuilder(context, i),
              ),
            ),
          ),
        ),
        if (widget.count > 1) ...[
          const SizedBox(height: 12),
          ContentDots(count: widget.count, index: index),
        ],
      ],
    );
  }
}

class ContentSectionHeader extends StatelessWidget {
  const ContentSectionHeader({
    super.key,
    required this.title,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: scheme.primary,
                minimumSize: const Size(44, 44),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(actionLabel!, style: const TextStyle(fontSize: 12)),
                  const SizedBox(width: 4),
                  const Icon(PhosphorIconsBold.arrowRight, size: 14),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Single-select filter chips in a horizontal strip.
class ContentChipBar extends StatelessWidget {
  const ContentChipBar({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
  });

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final on = i == selected;
          return Semantics(
            button: true,
            selected: on,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => onSelected(i),
                borderRadius: BorderRadius.circular(22),
                child: AnimatedContainer(
                  duration: _motion(context, 200),
                  curve: Curves.easeOut,
                  alignment: Alignment.center,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: on ? scheme.primary : scheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: on ? scheme.primary : scheme.outlineVariant,
                    ),
                  ),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: on ? scheme.onPrimary : scheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
