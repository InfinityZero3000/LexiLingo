import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

/// Get personalized greeting based on time of day
String getTimeBasedGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 5) {
    return 'Good night';
  } else if (hour < 12) {
    return 'Good morning';
  } else if (hour < 17) {
    return 'Good afternoon';
  } else if (hour < 21) {
    return 'Good evening';
  } else {
    return 'Good night';
  }
}

/// Get icon based on time of day
IconData getTimeBasedIcon() {
  final hour = DateTime.now().hour;
  if (hour < 5) {
    return Icons.nightlight_round;
  } else if (hour < 12) {
    return Icons.wb_sunny;
  } else if (hour < 17) {
    return Icons.wb_cloudy;
  } else if (hour < 21) {
    return Icons.wb_twilight;
  } else {
    return Icons.nightlight_round;
  }
}

/// Get icon color based on time of day
Color getTimeBasedIconColor() {
  final hour = DateTime.now().hour;
  if (hour < 5) {
    return const Color(0xFF5C6BC0); // Indigo for night
  } else if (hour < 12) {
    return const Color(0xFFFFB300); // Amber for morning
  } else if (hour < 17) {
    return const Color(0xFF42A5F5); // Blue for afternoon
  } else if (hour < 21) {
    return const Color(0xFFFF7043); // Deep orange for evening
  } else {
    return const Color(0xFF5C6BC0); // Indigo for night
  }
}

/// Personalized greeting header with glassmorphism
class PersonalizedGreetingHeader extends StatelessWidget {
  final String userName;
  final int totalXP;
  final String? avatarUrl;
  final int notificationCount;
  final VoidCallback? onNotificationTap;
  final VoidCallback? onAvatarTap;

  const PersonalizedGreetingHeader({
    super.key,
    required this.userName,
    required this.totalXP,
    this.avatarUrl,
    this.notificationCount = 0,
    this.onNotificationTap,
    this.onAvatarTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final greeting = getTimeBasedGreeting();
    final timeIcon = getTimeBasedIcon();
    final iconColor = getTimeBasedIconColor();

    return Container(
      margin: const EdgeInsets.all(16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [
                        Colors.white.withValues(alpha: 0.1),
                        Colors.white.withValues(alpha: 0.05),
                      ]
                    : [
                        const Color(0xFF667eea).withValues(alpha: 0.15),
                        const Color(0xFF764ba2).withValues(alpha: 0.1),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.white.withValues(alpha: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Avatar with animated ring
                GestureDetector(
                  onTap: onAvatarTap,
                  child: _AnimatedAvatarRing(
                    avatarUrl: avatarUrl,
                    size: 56,
                  ),
                ),
                const SizedBox(width: 14),
                // Greeting text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            greeting,
                            style: TextStyle(
                              fontSize: 14,
                              color: isDark ? Colors.grey[400] : Colors.grey[600],
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Icon(
                            timeIcon,
                            size: 16,
                            color: iconColor,
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        userName,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      _AnimatedXPCounter(xp: totalXP),
                    ],
                  ),
                ),
                // Notification bell
                _NotificationBell(
                  count: notificationCount,
                  onTap: onNotificationTap,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Animated avatar ring with gradient border
class _AnimatedAvatarRing extends StatefulWidget {
  final String? avatarUrl;
  final double size;

  const _AnimatedAvatarRing({
    this.avatarUrl,
    this.size = 56,
  });

  @override
  State<_AnimatedAvatarRing> createState() => _AnimatedAvatarRingState();
}

class _AnimatedAvatarRingState extends State<_AnimatedAvatarRing>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              startAngle: _controller.value * 2 * math.pi,
              colors: const [
                Color(0xFF667eea),
                Color(0xFF764ba2),
                Color(0xFFf093fb),
                Color(0xFF667eea),
              ],
            ),
          ),
          padding: const EdgeInsets.all(3),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Theme.of(context).scaffoldBackgroundColor,
            ),
            padding: const EdgeInsets.all(2),
            child: ClipOval(
              child: widget.avatarUrl != null
                  ? Image.network(
                      widget.avatarUrl!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildDefaultAvatar(),
                    )
                  : _buildDefaultAvatar(),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    return Container(
      color: const Color(0xFF667eea).withValues(alpha: 0.2),
      child: const Icon(
        Icons.person,
        color: Color(0xFF667eea),
        size: 28,
      ),
    );
  }
}

/// Animated XP counter with sparkle effect
class _AnimatedXPCounter extends StatefulWidget {
  final int xp;

  const _AnimatedXPCounter({required this.xp});

  @override
  State<_AnimatedXPCounter> createState() => _AnimatedXPCounterState();
}

class _AnimatedXPCounterState extends State<_AnimatedXPCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _sparkleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _sparkleAnimation = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatXP(int xp) {
    if (xp >= 1000000) {
      return '${(xp / 1000000).toStringAsFixed(1)}M';
    } else if (xp >= 1000) {
      return '${(xp / 1000).toStringAsFixed(1)}K';
    }
    return xp.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _sparkleAnimation,
      builder: (context, child) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color(0xFFFBBF24).withValues(alpha: 0.2),
                    const Color(0xFFF59E0B).withValues(alpha: 0.15),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: _sparkleAnimation.value,
                    child: const Icon(
                      Icons.star_rounded,
                      size: 14,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatXP(widget.xp)} XP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFFF59E0B),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Notification bell with badge
class _NotificationBell extends StatefulWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationBell({
    this.count = 0,
    this.onTap,
  });

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell>
    with SingleTickerProviderStateMixin {
  late AnimationController _shakeController;
  late Animation<double> _shakeAnimation;

  @override
  void initState() {
    super.initState();
    _shakeController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _shakeAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0, end: 0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.1, end: -0.1), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.08), weight: 1),
      TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.05), weight: 1),
      TweenSequenceItem(tween: Tween(begin: -0.05, end: 0), weight: 1),
    ]).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

    // Shake if there are notifications
    if (widget.count > 0) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _shakeController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count) {
      _shakeController.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shakeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _shakeAnimation,
        builder: (context, child) {
          return Transform.rotate(
            angle: _shakeAnimation.value,
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[800] : Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Icon(
                    Icons.notifications_outlined,
                    color: isDark ? Colors.white : Colors.grey[700],
                    size: 22,
                  ),
                  if (widget.count > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: Color(0xFFEF4444),
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          widget.count > 9 ? '9+' : widget.count.toString(),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Animated fire streak card
class AnimatedStreakCard extends StatefulWidget {
  final int streakDays;
  final int longestStreak;
  final bool isActiveToday;
  final VoidCallback? onTap;

  const AnimatedStreakCard({
    super.key,
    required this.streakDays,
    this.longestStreak = 0,
    this.isActiveToday = false,
    this.onTap,
  });

  @override
  State<AnimatedStreakCard> createState() => _AnimatedStreakCardState();
}

class _AnimatedStreakCardState extends State<AnimatedStreakCard>
    with TickerProviderStateMixin {
  late AnimationController _flameController;
  late AnimationController _pulseController;
  late Animation<double> _flameAnimation;
  late Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    
    // Flame flickering animation
    _flameController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    )..repeat(reverse: true);

    _flameAnimation = Tween<double>(begin: 0.9, end: 1.1).animate(
      CurvedAnimation(parent: _flameController, curve: Curves.easeInOut),
    );

    // Pulse animation for glow
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _flameController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: Listenable.merge([_flameAnimation, _pulseAnimation]),
        builder: (context, child) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: widget.streakDays > 0
                    ? [
                        const Color(0xFFFF6B35).withValues(alpha: 0.15),
                        const Color(0xFFFF9A56).withValues(alpha: 0.1),
                      ]
                    : [
                        Colors.grey.withValues(alpha: 0.1),
                        Colors.grey.withValues(alpha: 0.05),
                      ],
              ),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: widget.streakDays > 0
                    ? const Color(0xFFFF6B35).withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.2),
              ),
              boxShadow: widget.streakDays > 0
                  ? [
                      BoxShadow(
                        color: const Color(0xFFFF6B35).withValues(alpha: _pulseAnimation.value * 0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
                // Animated fire icon
                _buildAnimatedFire(),
                const SizedBox(width: 16),
                // Streak info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.streakDays} Day Streak',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: widget.streakDays > 0
                              ? const Color(0xFFFF6B35)
                              : Colors.grey,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (widget.longestStreak > 0)
                        Text(
                          'Longest: ${widget.longestStreak} days',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      const SizedBox(height: 8),
                      // Week calendar
                      _buildWeekCalendar(),
                    ],
                  ),
                ),
                // Status indicator
                if (widget.isActiveToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: Color(0xFF10B981),
                        ),
                        SizedBox(width: 4),
                        Text(
                          'Done',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF10B981),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildAnimatedFire() {
    return AnimatedBuilder(
      animation: _flameAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: _flameAnimation.value,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow effect
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: widget.streakDays > 0
                        ? [
                            const Color(0xFFFF6B35).withValues(alpha: 0.3),
                            Colors.transparent,
                          ]
                        : [
                            Colors.grey.withValues(alpha: 0.2),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
              // Fire icon
              Icon(
                Icons.local_fire_department_rounded,
                size: 40,
                color: widget.streakDays > 0
                    ? const Color(0xFFFF6B35)
                    : Colors.grey,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeekCalendar() {
    final now = DateTime.now();
    final days = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    final currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday

    return Row(
      children: List.generate(7, (index) {
        final dayNumber = index + 1;
        final isPast = dayNumber < currentWeekday;
        final isToday = dayNumber == currentWeekday;
        final isActive = isPast || (isToday && widget.isActiveToday);

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Column(
            children: [
              Text(
                days[index],
                style: TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.w500,
                  color: isToday
                      ? const Color(0xFFFF6B35)
                      : Colors.grey[500],
                ),
              ),
              const SizedBox(height: 3),
              Container(
                width: 18,
                height: 18,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? const Color(0xFFFF6B35)
                      : Colors.transparent,
                  border: Border.all(
                    color: isToday
                        ? const Color(0xFFFF6B35)
                        : isActive
                            ? Colors.transparent
                            : Colors.grey.withValues(alpha: 0.3),
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: isActive
                    ? const Icon(
                        Icons.local_fire_department,
                        size: 10,
                        color: Colors.white,
                      )
                    : null,
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Skeleton loading widget with shimmer effect
class SkeletonLoader extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonLoader({
    super.key,
    this.width = double.infinity,
    required this.height,
    this.borderRadius = 12,
  });

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat();

    _animation = Tween<double>(begin: -2, end: 2).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[200]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;

    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) {
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            gradient: LinearGradient(
              begin: Alignment(_animation.value - 1, 0),
              end: Alignment(_animation.value, 0),
              colors: [
                baseColor,
                highlightColor,
                baseColor,
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Card skeleton for course/lesson cards
class CardSkeleton extends StatelessWidget {
  final bool isHorizontal;

  const CardSkeleton({
    super.key,
    this.isHorizontal = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isHorizontal) {
      return Container(
        width: 280,
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonLoader(height: 120, borderRadius: 12),
            SizedBox(height: 12),
            SkeletonLoader(height: 16, width: 180),
            SizedBox(height: 8),
            SkeletonLoader(height: 12, width: 120),
            SizedBox(height: 12),
            SkeletonLoader(height: 8, borderRadius: 4),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          SkeletonLoader(width: 80, height: 80, borderRadius: 12),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SkeletonLoader(height: 16),
                SizedBox(height: 8),
                SkeletonLoader(height: 12, width: 150),
                SizedBox(height: 8),
                SkeletonLoader(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
