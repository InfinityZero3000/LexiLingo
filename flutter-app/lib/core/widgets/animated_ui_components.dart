import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';

/// Animated Notification Badge
/// Shows a pulsing badge when there are unread notifications
class AnimatedNotificationBadge extends StatelessWidget {
  final int count;
  final Widget child;
  final Color badgeColor;
  final bool showPulse;

  const AnimatedNotificationBadge({
    super.key,
    required this.count,
    required this.child,
    this.badgeColor = Colors.red,
    this.showPulse = true,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return child;
    }

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -4,
          top: -4,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Pulse animation behind badge
              if (showPulse && count > 0)
                PulseAnimation(
                  color: badgeColor.withOpacity(0.5),
                  maxRadius: 12,
                  duration: const Duration(milliseconds: 1500),
                  child: const SizedBox(width: 24, height: 24),
                ),
              // Badge count
              Container(
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(
                  minWidth: 18,
                  minHeight: 18,
                ),
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: count > 9 ? BoxShape.rectangle : BoxShape.circle,
                  borderRadius: count > 9 ? BorderRadius.circular(9) : null,
                  boxShadow: [
                    BoxShadow(
                      color: badgeColor.withOpacity(0.4),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    count > 99 ? '99+' : count.toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Animated List Item Wrapper
/// Adds slide + fade entrance animation to list items
class AnimatedListItem extends StatelessWidget {
  final Widget child;
  final int index;
  final Duration duration;
  final Duration delayPerItem;

  const AnimatedListItem({
    super.key,
    required this.child,
    required this.index,
    this.duration = const Duration(milliseconds: 400),
    this.delayPerItem = const Duration(milliseconds: 50),
  });

  @override
  Widget build(BuildContext context) {
    return SlideFadeTransition(
      duration: duration,
      delay: Duration(milliseconds: delayPerItem.inMilliseconds * index),
      beginOffset: const Offset(0, 20),
      child: child,
    );
  }
}

/// Animated Card with BreathingGlow
/// Highlights important cards with a breathing glow effect
class HighlightedCard extends StatelessWidget {
  final Widget child;
  final bool isHighlighted;
  final Color glowColor;
  final BorderRadius? borderRadius;

  const HighlightedCard({
    super.key,
    required this.child,
    this.isHighlighted = false,
    this.glowColor = Colors.amber,
    this.borderRadius,
  });

  @override
  Widget build(BuildContext context) {
    if (!isHighlighted) {
      return child;
    }

    return BreathingGlow(
      glowColor: glowColor,
      maxBlur: 12,
      duration: const Duration(milliseconds: 2000),
      child: child,
    );
  }
}

/// Animated Star Rating Display
/// Shows animated stars for ratings
class AnimatedRatingStars extends StatelessWidget {
  final double rating;
  final int maxRating;
  final double size;
  final Color filledColor;
  final Color unfilledColor;

  const AnimatedRatingStars({
    super.key,
    required this.rating,
    this.maxRating = 5,
    this.size = 20,
    this.filledColor = Colors.amber,
    this.unfilledColor = Colors.grey,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedStarRating(
      rating: rating,
      starCount: maxRating,
      size: size,
      filledColor: filledColor,
      unfilledColor: unfilledColor,
    );
  }
}

/// Quick Action Button with Ripple
/// Button with ripple animation on tap
class AnimatedActionButton extends StatefulWidget {
  final VoidCallback onTap;
  final IconData icon;
  final String label;
  final Color color;
  final double size;

  const AnimatedActionButton({
    super.key,
    required this.onTap,
    required this.icon,
    required this.label,
    this.color = Colors.blue,
    this.size = 56,
  });

  @override
  State<AnimatedActionButton> createState() => _AnimatedActionButtonState();
}

class _AnimatedActionButtonState extends State<AnimatedActionButton> {
  bool _showRipple = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _showRipple = true),
      onTapUp: (_) {
        widget.onTap();
        Future.delayed(const Duration(milliseconds: 300), () {
          if (mounted) setState(() => _showRipple = false);
        });
      },
      onTapCancel: () => setState(() => _showRipple = false),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (_showRipple)
                  RippleEffect(
                    rippleColor: widget.color,
                    child: SizedBox(
                      width: widget.size,
                      height: widget.size,
                    ),
                  ),
                Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    color: widget.color.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    color: widget.color,
                    size: widget.size * 0.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

/// Favorite Button with Heartbeat
/// Animated heart button for favorites
class AnimatedFavoriteButton extends StatefulWidget {
  final bool isFavorite;
  final ValueChanged<bool> onChanged;
  final double size;

  const AnimatedFavoriteButton({
    super.key,
    required this.isFavorite,
    required this.onChanged,
    this.size = 32,
  });

  @override
  State<AnimatedFavoriteButton> createState() => _AnimatedFavoriteButtonState();
}

class _AnimatedFavoriteButtonState extends State<AnimatedFavoriteButton> {
  late bool _isFavorite;

  @override
  void initState() {
    super.initState();
    _isFavorite = widget.isFavorite;
  }

  @override
  void didUpdateWidget(AnimatedFavoriteButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isFavorite != widget.isFavorite) {
      _isFavorite = widget.isFavorite;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        setState(() => _isFavorite = !_isFavorite);
        widget.onChanged(_isFavorite);
      },
      child: SizedBox(
        width: widget.size,
        height: widget.size,
        child: _isFavorite
            ? HeartbeatAnimation(
                size: widget.size,
                color: Colors.red,
                isActive: true,
              )
            : Icon(
                Icons.favorite_border,
                size: widget.size,
                color: Colors.grey,
              ),
      ),
    );
  }
}
