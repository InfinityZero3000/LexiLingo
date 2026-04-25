import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/network_avatar_image.dart';

/// Get personalized greeting based on time of day
String getTimeBasedGreeting() {
  final hour = DateTime.now().hour;
  if (hour < 5) {
    return 'home.greetingNight'.tr();
  } else if (hour < 12) {
    return 'home.greetingMorning'.tr();
  } else if (hour < 17) {
    return 'home.greetingAfternoon'.tr();
  } else if (hour < 21) {
    return 'home.greetingEvening'.tr();
  } else {
    return 'home.greetingNight'.tr();
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
Color getTimeBasedIconColor({required bool isDark}) {
  final hour = DateTime.now().hour;
  if (hour < 5) {
    return AppColorRoles.primary(isDark);
  } else if (hour < 12) {
    return AppColors.warning; // Amber for morning
  } else if (hour < 17) {
    return AppColorRoles.primary(isDark);
  } else if (hour < 21) {
    return AppColors.orange; // Deep orange for evening
  } else {
    return AppColorRoles.primary(isDark);
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
    final iconColor = getTimeBasedIconColor(isDark: isDark);
    final accent = AppColorRoles.primary(isDark);

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? AppColors.surfaceDarkMuted
            : AppColors.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? accent.withValues(alpha: 0.25)
              : AppColors.primary.withValues(alpha: 0.15),
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
              useDarkAccent: isDark,
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
                    Icon(timeIcon, size: 16, color: iconColor),
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
          _NotificationBell(count: notificationCount, onTap: onNotificationTap),
        ],
      ),
    );
  }
}

/// Animated avatar ring with gradient border
class _AnimatedAvatarRing extends StatefulWidget {
  final String? avatarUrl;
  final double size;
  final bool useDarkAccent;

  const _AnimatedAvatarRing({
    this.avatarUrl,
    this.size = 56,
    this.useDarkAccent = false,
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
        final accent = AppColorRoles.primary(widget.useDarkAccent);
        return Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: SweepGradient(
              startAngle: _controller.value * 2 * math.pi,
              colors: [accent, AppColors.purple, AppColors.purple, accent],
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
              child: NetworkAvatarImage(
                imageUrl: widget.avatarUrl,
                fit: BoxFit.cover,
                fallback: _buildDefaultAvatar(),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDefaultAvatar() {
    final accent = AppColorRoles.primary(widget.useDarkAccent);
    return Container(
      color: accent.withValues(alpha: 0.2),
      child: Icon(Icons.person, color: accent, size: 28),
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

    _sparkleAnimation = Tween<double>(
      begin: 0.6,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
                    AppColors.accentYellow.withValues(alpha: 0.2),
                    AppColors.orange.withValues(alpha: 0.15),
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
                      color: AppColors.orange,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_formatXP(widget.xp)} XP',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.orange,
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

  const _NotificationBell({this.count = 0, this.onTap});

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

    _shakeAnimation = TweenSequence<double>(
      [
        TweenSequenceItem(tween: Tween(begin: 0, end: 0.1), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.1, end: -0.1), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -0.1, end: 0.08), weight: 1),
        TweenSequenceItem(tween: Tween(begin: 0.08, end: -0.05), weight: 1),
        TweenSequenceItem(tween: Tween(begin: -0.05, end: 0), weight: 1),
      ],
    ).animate(CurvedAnimation(parent: _shakeController, curve: Curves.easeOut));

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
                color: isDark ? Colors.grey[800] : AppColors.grey100,
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
                        decoration: BoxDecoration(
                          color: AppColors.dangerGradient[0],
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        child: Text(
                          widget.count > 9 ? '9+' : widget.count.toString(),
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.surface,
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
  final List<bool>? weeklyActivity;
  final List<double>? weeklyProgressPercentages;
  final VoidCallback? onTap;

  const AnimatedStreakCard({
    super.key,
    required this.streakDays,
    this.longestStreak = 0,
    this.isActiveToday = false,
    this.weeklyActivity,
    this.weeklyProgressPercentages,
    this.onTap,
  });

  @override
  State<AnimatedStreakCard> createState() => _AnimatedStreakCardState();
}

class _AnimatedStreakCardState extends State<AnimatedStreakCard>
    with TickerProviderStateMixin {
  late AnimationController _flameController;
  late Animation<double> _flameAnimation;

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
  }

  @override
  void dispose() {
    _flameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final weekly = widget.weeklyActivity ?? List.filled(7, false);
    final completedDays = weekly.where((active) => active).length;
    final weekProgress = completedDays / 7;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      decoration: BoxDecoration(
        gradient: isDark
            ? LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [AppColors.surfaceDark, const Color(0xFF1A1F26)],
              )
            : const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFFFF6F0), Color(0xFFFFEFE3)],
              ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.08)
              : const Color(0xFFF4DCCB),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.06),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildAnimatedFire(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'home.dayStreakCount'.tr(
                        namedArgs: {'count': '${widget.streakDays}'},
                      ),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                        color: isDark ? Colors.white : AppColors.textDark,
                      ),
                    ),
                    Text(
                      widget.isActiveToday
                          ? 'home.fireToday'.tr()
                          : 'home.completeLessonToday'.tr(),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: isDark
                            ? Colors.white70
                            : const Color(0xFF5F6573),
                      ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: widget.onTap,
                style: TextButton.styleFrom(
                  foregroundColor: isDark
                      ? AppColors.primaryDarkModeSoft
                      : AppColors.teal,
                  backgroundColor: isDark
                      ? AppColors.accentMintDark.withValues(alpha: 0.45)
                      : AppColors.accentMint.withValues(alpha: 0.16),
                  textStyle: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(999),
                    side: BorderSide(
                      color: isDark
                          ? AppColors.accentMint.withValues(alpha: 0.55)
                          : AppColors.accentMint.withValues(alpha: 0.35),
                    ),
                  ),
                ),
                icon: const Icon(Icons.calendar_month_rounded, size: 14),
                label: Text('home.calendar'.tr()),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildWeekCalendar(),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              minHeight: 7,
              value: weekProgress,
              backgroundColor: isDark
                  ? Colors.white.withValues(alpha: 0.1)
                  : const Color(0xFFF3E4D7),
              valueColor: AlwaysStoppedAnimation<Color>(
                widget.isActiveToday
                    ? const Color(0xFFFF6B35)
                    : const Color(0xFFFF915F),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'home.activeDaysThisWeek'.tr(namedArgs: {'count': '$completedDays'}),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white60 : const Color(0xFF7A6A5F),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnimatedFire() {
    final hasStreak = widget.streakDays > 0;
    return AnimatedBuilder(
      animation: _flameAnimation,
      builder: (context, child) {
        return Transform.scale(
          scale: hasStreak && widget.isActiveToday
              ? _flameAnimation.value
              : 1.0,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Glow effect
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: hasStreak
                        ? [
                            const Color(0xFFFF6B35).withValues(alpha: 0.38),
                            const Color(0xFFFF3D00).withValues(alpha: 0.16),
                            Colors.transparent,
                          ]
                        : [
                            Colors.grey.withValues(alpha: 0.18),
                            Colors.transparent,
                          ],
                  ),
                ),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: hasStreak
                      ? Colors.white.withValues(alpha: 0.14)
                      : Colors.grey.withValues(alpha: 0.12),
                  border: Border.all(
                    color: hasStreak
                        ? const Color(0xFFFF7A45).withValues(alpha: 0.55)
                        : Colors.grey.withValues(alpha: 0.35),
                  ),
                ),
                child: Center(
                  child: hasStreak
                      ? ShaderMask(
                          shaderCallback: (bounds) => const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFFFFB74D),
                              Color(0xFFFF7043),
                              Color(0xFFE53935),
                            ],
                          ).createShader(bounds),
                          child: const Icon(
                            Icons.local_fire_department_rounded,
                            size: 30,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(
                          Icons.local_fire_department_rounded,
                          size: 30,
                          color: AppColors.grey500,
                        ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWeekCalendar() {
    final now = DateTime.now();
    final days = [
      'home.weekdayMonShort'.tr(),
      'home.weekdayTueShort'.tr(),
      'home.weekdayWedShort'.tr(),
      'home.weekdayThuShort'.tr(),
      'home.weekdayFriShort'.tr(),
      'home.weekdaySatShort'.tr(),
      'home.weekdaySunShort'.tr(),
    ];
    final currentWeekday = now.weekday; // 1 = Monday, 7 = Sunday
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Use real per-day activity data when available; fall back to no highlights
    final activity = widget.weeklyActivity ?? List.filled(7, false);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (index) {
        final dayNumber = index + 1; // 1=Mon … 7=Sun
        final isToday = dayNumber == currentWeekday;
        final isActive = activity[index];

        return Expanded(
          child: Column(
            children: [
              Text(
                days[index],
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isToday ? FontWeight.w800 : FontWeight.w600,
                  color: isToday
                      ? AppColors.deepOrange
                      : isDark
                      ? Colors.white54
                      : const Color(0xFF9A8F86),
                ),
              ),
              const SizedBox(height: 8),
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive
                      ? AppColors.deepOrange
                      : (isDark
                            ? Colors.white.withValues(alpha: 0.04)
                            : const Color(0xFFF8EBDF)),
                  border: Border.all(
                    color: isToday
                        ? AppColors.deepOrange
                        : isActive
                        ? Colors.transparent
                        : (isDark
                              ? Colors.white.withValues(alpha: 0.15)
                              : const Color(0xFFE8CCB6)),
                    width: isToday ? 2 : 1,
                  ),
                ),
                child: isActive
                    ? Icon(
                        Icons.local_fire_department,
                        size: 14,
                        color: AppColors.surfaceLight,
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

    _animation = Tween<double>(
      begin: -2,
      end: 2,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
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
              colors: [baseColor, highlightColor, baseColor],
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

  const CardSkeleton({super.key, this.isHorizontal = false});

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
