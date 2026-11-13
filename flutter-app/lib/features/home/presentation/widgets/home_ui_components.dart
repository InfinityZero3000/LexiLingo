import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Zero when the learner asked the OS for reduced motion.
Duration homeMotion(BuildContext context, int milliseconds) =>
    MediaQuery.disableAnimationsOf(context)
    ? Duration.zero
    : Duration(milliseconds: milliseconds);

enum DayPart {
  morning('home.greetingPhraseMorning', 'home.greetingMorning'),
  afternoon('home.greetingPhraseAfternoon', 'home.greetingAfternoon'),
  evening('home.greetingPhraseEvening', 'home.greetingEvening'),
  night('home.greetingPhraseNight', 'home.greetingNight');

  const DayPart(this.phraseKey, this.meaningKey);

  /// The English phrase is learning content, so it stays English everywhere;
  /// [meaningKey] is the learner's own-language gloss.
  final String phraseKey;
  final String meaningKey;

  static DayPart of(int hour) {
    if (hour < 5) return DayPart.night;
    if (hour < 12) return DayPart.morning;
    if (hour < 18) return DayPart.afternoon;
    if (hour < 22) return DayPart.evening;
    return DayPart.night;
  }

  static DayPart now() => DayPart.of(DateTime.now().hour);

  IconData get icon => switch (this) {
    DayPart.morning => Icons.wb_sunny_rounded,
    DayPart.afternoon => Icons.wb_twilight_rounded,
    DayPart.evening || DayPart.night => Icons.nightlight_round,
  };

  Color color(bool isDark) => switch (this) {
    DayPart.morning => AppColors.warning,
    DayPart.afternoon => AppColors.orange,
    DayPart.evening || DayPart.night => AppColorRoles.primary(isDark),
  };
}

/// Counts from 0 to [value] on first build and between values after that.
class CountUpText extends StatelessWidget {
  const CountUpText({
    super.key,
    required this.value,
    required this.format,
    this.style,
    this.duration = const Duration(milliseconds: 600),
  });

  final int value;
  final String Function(int value) format;
  final TextStyle? style;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<int>(
      tween: IntTween(begin: 0, end: value),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : duration,
      curve: Curves.easeOutCubic,
      builder: (context, current, _) => Text(
        format(current),
        style: style,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

String formatXp(int xp) {
  if (xp >= 1000000) return '${(xp / 1000000).toStringAsFixed(1)}M';
  if (xp >= 1000) return '${(xp / 1000).toStringAsFixed(1)}K';
  return xp.toString();
}

/// Greeting, name, XP and the bell — no card, so the hero below owns the eye.
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final dayPart = DayPart.now();
    final phrase = dayPart.phraseKey.tr();
    final meaning = dayPart.meaningKey.tr();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'home.openProfile'.tr(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onAvatarTap,
              child: _AvatarRing(avatarUrl: avatarUrl, isDark: isDark),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: phrase,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: AppColorRoles.textPrimary(isDark),
                        ),
                      ),
                      WidgetSpan(
                        alignment: PlaceholderAlignment.middle,
                        child: Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: Icon(
                            dayPart.icon,
                            size: 18,
                            color: dayPart.color(isDark),
                          ),
                        ),
                      ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: userName,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: AppColorRoles.textSecondary(isDark),
                        ),
                      ),
                      if (meaning != phrase)
                        TextSpan(
                          text: '  ·  $meaning',
                          style: TextStyle(
                            color: AppColorRoles.textMuted(isDark),
                          ),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                _XpPill(xp: totalXP),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _NotificationBell(count: notificationCount, onTap: onNotificationTap),
        ],
      ),
    );
  }
}

class _AvatarRing extends StatelessWidget {
  const _AvatarRing({required this.avatarUrl, required this.isDark});

  final String? avatarUrl;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final accent = AppColorRoles.primary(isDark);
    return Container(
      width: 48,
      height: 48,
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, AppColors.purple],
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Theme.of(context).scaffoldBackgroundColor,
        ),
        child: ClipOval(
          child: NetworkAvatarImage(
            imageUrl: avatarUrl,
            fit: BoxFit.cover,
            fallback: ColoredBox(
              color: accent.withValues(alpha: 0.2),
              child: Icon(Icons.person_rounded, color: accent, size: 24),
            ),
          ),
        ),
      ),
    );
  }
}

class _XpPill extends StatelessWidget {
  const _XpPill({required this.xp});

  final int xp;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fg = isDark ? AppColors.orange : AppColors.warningDark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.accentYellow.withValues(alpha: isDark ? 0.18 : 0.28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: AppColors.orange.withValues(alpha: 0.4),
          width: 1.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.star_rounded, size: 16, color: fg),
          const SizedBox(width: 4),
          CountUpText(
            value: xp,
            format: (value) => '${formatXp(value)} XP',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w800,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationBell extends StatefulWidget {
  final int count;
  final VoidCallback? onTap;

  const _NotificationBell({this.count = 0, this.onTap});

  @override
  State<_NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<_NotificationBell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shakeController;
  late final Animation<double> _shakeAnimation;
  bool _shookOnEntry = false;

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
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_shookOnEntry) return;
    _shookOnEntry = true;
    if (widget.count > 0 && !MediaQuery.disableAnimationsOf(context)) {
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) _shakeController.forward();
      });
    }
  }

  @override
  void didUpdateWidget(_NotificationBell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count > oldWidget.count &&
        !MediaQuery.disableAnimationsOf(context)) {
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: 'home.notificationsSemantics'.tr(
        namedArgs: {'count': '${widget.count}'},
      ),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _shakeAnimation,
          builder: (context, child) =>
              Transform.rotate(angle: _shakeAnimation.value, child: child),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: isDark ? AppColors.surfaceDarkElevated : AppColors.grey100,
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark ? AppColors.borderDarkSoft : AppColors.grey300,
                width: 1.5,
              ),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  PhosphorIconsBold.bell,
                  size: 22,
                  color: AppColorRoles.textPrimary(isDark),
                ),
                if (widget.count > 0)
                  Positioned(
                    top: 2,
                    right: 2,
                    child: ExcludeSemantics(
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 18,
                          minHeight: 18,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: AppColors.errorBright,
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: theme.scaffoldBackgroundColor,
                            width: 1.5,
                          ),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          widget.count > 9 ? '9+' : '${widget.count}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
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
    final baseColor = isDark ? AppColors.grey800 : AppColors.grey200;
    final highlightColor = isDark ? AppColors.grey700 : AppColors.grey100;

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
