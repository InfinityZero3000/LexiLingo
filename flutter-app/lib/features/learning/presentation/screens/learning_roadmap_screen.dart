import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/widgets.dart';
import 'package:lexilingo_app/features/learning/data/models/roadmap_model.dart';
import 'package:lexilingo_app/features/learning/presentation/painters/roadmap_path_painter.dart';
import 'package:lexilingo_app/features/learning/presentation/providers/learning_provider.dart';
import 'package:lexilingo_app/features/learning/presentation/screens/learning_session_screen.dart';
import 'package:lexilingo_app/features/learning/presentation/widgets/roadmap_header_widget.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

// ─────────────────────────────────────────────────────────────
// Layout constants
// ─────────────────────────────────────────────────────────────
const double _kNodeDiameter = 84.0;
const double _kNodeRadius = _kNodeDiameter / 2;
const double _kRowH = 136.0; // vertical space per lesson node
const double _kBannerH = 92.0; // height of unit chapter banner
const double _kBannerTopMargin = 28.0; // gap above each banner
const double _kTopPad = 12.0;
const double _kBotPad = 120.0;

/// Sine-wave x positions (normalized 0..1).
/// 8-step cycle gives a smooth winding road from edge to edge.
const List<double> _kXCycle = [0.14, 0.32, 0.50, 0.68, 0.86, 0.68, 0.50, 0.32];

// ─────────────────────────────────────────────────────────────
// Internal layout data holders
// ─────────────────────────────────────────────────────────────
class _NodeLayout {
  final Offset center;
  final LessonProgressModel lesson;
  final UnitRoadmapModel unit;
  final int globalIndex;

  _NodeLayout({
    required this.center,
    required this.lesson,
    required this.unit,
    required this.globalIndex,
  });

  Color get baseColor => _parseHex(unit.backgroundColor);

  Color get nodeColor {
    if (lesson.isLocked) return AppColors.grey400;
    if (lesson.isCompleted) return AppColors.greenSuccessBright;
    if (globalIndex <= 3) {
      return AppColors.roadmapEarlyStepDarkPalette[globalIndex - 1];
    }
    if (lesson.isCurrent) {
      return _ensureRoadmapContrast(_mixWithWhite(baseColor, 0.40));
    }
    return _ensureRoadmapContrast(
      _mixWithWhite(baseColor, 0.30),
    ).withValues(alpha: 0.92);
  }

  Color get pathColor {
    if (lesson.isCompleted) return const Color(0xFF66BB6A);
    return _ensureRoadmapContrast(
      baseColor,
    ).withValues(alpha: lesson.isLocked ? 0.30 : 0.62);
  }
}

class _BannerLayout {
  final double top;
  final UnitRoadmapModel unit;
  _BannerLayout({required this.top, required this.unit});
}

// ─────────────────────────────────────────────────────────────
// Main screen
// ─────────────────────────────────────────────────────────────

/// Zigzag (Duolingo-style) learning roadmap screen.
///
/// Lessons are positioned along a winding bezier path.
/// Each unit has a full-width chapter banner.
/// Tapping a node opens a bottom sheet with lesson details and a CTA.
class LearningRoadmapScreen extends StatefulWidget {
  final String courseId;
  final String courseTitle;

  const LearningRoadmapScreen({
    super.key,
    required this.courseId,
    required this.courseTitle,
  });

  @override
  State<LearningRoadmapScreen> createState() => _LearningRoadmapScreenState();
}

class _LearningRoadmapScreenState extends State<LearningRoadmapScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LearningProvider>().loadRoadmap(widget.courseId);
    });
  }

  // ── Layout computation ─────────────────────────────────────

  double _totalH(CourseRoadmapModel roadmap) {
    double h = _kTopPad;
    for (final unit in roadmap.units) {
      h += _kBannerTopMargin + _kBannerH + 48.0;
      h += unit.lessons.length * _kRowH;
    }
    return h + _kBotPad;
  }

  ({List<_NodeLayout> nodes, List<_BannerLayout> banners}) _buildLayouts(
    CourseRoadmapModel roadmap,
    double width,
  ) {
    final nodes = <_NodeLayout>[];
    final banners = <_BannerLayout>[];
    double y = _kTopPad;
    int gi = 0;

    for (final unit in roadmap.units) {
      // Banner
      y += _kBannerTopMargin;
      banners.add(_BannerLayout(top: y, unit: unit));
      y += _kBannerH + 48.0;

      // Nodes
      for (final lesson in unit.lessons) {
        final xNorm = _kXCycle[gi % _kXCycle.length];
        final cx = (xNorm * width).clamp(
          _kNodeRadius + 8,
          width - _kNodeRadius - 8,
        );
        final cy = y + _kNodeRadius;
        nodes.add(
          _NodeLayout(
            center: Offset(cx, cy),
            lesson: lesson,
            unit: unit,
            globalIndex: gi + 1,
          ),
        );
        y += _kRowH;
        gi++;
      }
    }

    return (nodes: nodes, banners: banners);
  }

  // ── Build ──────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          image: DecorationImage(
            image: AssetImage(
              'assets/background-roadmap/background-roadmap.png',
            ),
            fit: BoxFit.fitHeight,
            alignment: Alignment.center,
          ),
        ),
        child: Consumer<LearningProvider>(
          builder: (context, provider, _) {
            if (provider.isLoadingRoadmap) {
              return const LoadingScreen(message: 'Loading roadmap…');
            }
            if (provider.roadmapError != null) {
              return _ErrorView(
                error: provider.roadmapError!,
                onRetry: () => provider.loadRoadmap(widget.courseId),
              );
            }
            final roadmap = provider.courseRoadmap;
            if (roadmap == null || roadmap.units.isEmpty) {
              return const _EmptyView();
            }
            return _ZigzagRoadmap(
              roadmap: roadmap,
              courseId: widget.courseId,
              buildLayouts: _buildLayouts,
              totalH: _totalH,
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Zigzag roadmap body
// ─────────────────────────────────────────────────────────────

class _ZigzagRoadmap extends StatelessWidget {
  final CourseRoadmapModel roadmap;
  final String courseId;
  final Function(CourseRoadmapModel, double) buildLayouts;
  final Function(CourseRoadmapModel) totalH;

  const _ZigzagRoadmap({
    required this.roadmap,
    required this.courseId,
    required this.buildLayouts,
    required this.totalH,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: RoadmapHeaderWidget(
            roadmap: roadmap,
            onBack: () => Navigator.pop(context),
          ),
        ),
        SliverToBoxAdapter(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              final contentH = totalH(roadmap);
              final layouts =
                  buildLayouts(roadmap, width)
                      as ({
                        List<_NodeLayout> nodes,
                        List<_BannerLayout> banners,
                      });

              return SizedBox(
                height: contentH,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    // ── Winding path ──────────────────────────
                    Positioned.fill(
                      child: CustomPaint(
                        painter: RoadmapPathPainter(
                          nodeCenters: layouts.nodes
                              .map((n) => n.center)
                              .toList(),
                          segmentColors: List.generate(
                            layouts.nodes.length,
                            (i) => layouts.nodes[i].pathColor,
                          ),
                          nodeRadius: _kNodeRadius,
                        ),
                      ),
                    ),
                    // ── Unit banners ─────────────────────────
                    for (final b in layouts.banners)
                      Positioned(
                        top: b.top,
                        left: 0,
                        right: 0,
                        height: _kBannerH,
                        child: _UnitBanner(unit: b.unit),
                      ),
                    // ── Lesson nodes ─────────────────────────
                    for (final n in layouts.nodes)
                      Positioned(
                        left: n.center.dx - _kNodeRadius,
                        top: n.center.dy - _kNodeRadius,
                        width: _kNodeDiameter,
                        height: _kNodeDiameter,
                        child: _LessonNode(
                          layout: n,
                          onTap: n.lesson.isLocked
                              ? null
                              : () => _showLessonSheet(context, n, courseId),
                        ),
                      ),
                    // ── Current lesson label bubble ───────────
                    for (final n in layouts.nodes.where(
                      (n) => n.lesson.isCurrent,
                    ))
                      Positioned(
                        left: n.center.dx - 72,
                        top: n.center.dy - _kNodeRadius - 48,
                        width: 144,
                        child: _CurrentLessonLabel(
                          lesson: n.lesson,
                          color: n.baseColor,
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  void _showLessonSheet(BuildContext ctx, _NodeLayout n, String courseId) {
    showModalBottomSheet(
      context: ctx,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _LessonDetailSheet(layout: n, courseId: courseId),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Lesson node button
// ─────────────────────────────────────────────────────────────

class _LessonNode extends StatefulWidget {
  final _NodeLayout layout;
  final VoidCallback? onTap;
  const _LessonNode({required this.layout, this.onTap});

  @override
  State<_LessonNode> createState() => _LessonNodeState();
}

class _LessonNodeState extends State<_LessonNode>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      duration: const Duration(milliseconds: 1400),
      vsync: this,
    );
    _scale = Tween(
      begin: 1.0,
      end: 1.10,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    _glow = Tween(
      begin: 0.3,
      end: 0.8,
    ).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut));
    if (widget.layout.lesson.isCurrent) _pulse.repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lesson = widget.layout.lesson;
    final color = widget.layout.nodeColor;

    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _pulse,
        builder: (_, __) {
          return Transform.scale(
            scale: lesson.isCurrent ? _scale.value : 1.0,
            child: Container(
              width: _kNodeDiameter,
              height: _kNodeDiameter,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: lesson.isLocked
                      ? AppColors.grey300
                      : Colors.white.withValues(alpha: 0.7),
                  width: 3.5,
                ),
                boxShadow: lesson.isLocked
                    ? null
                    : [
                        BoxShadow(
                          color: color.withValues(
                            alpha: lesson.isCurrent ? _glow.value : 0.4,
                          ),
                          blurRadius: lesson.isCurrent ? 20 : 10,
                          spreadRadius: lesson.isCurrent ? 3 : 1,
                        ),
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  // Main icon
                  _nodeIcon(lesson),
                  // Stars badge (top-right)
                  if (lesson.isCompleted && lesson.starsEarned > 0)
                    Positioned(
                      top: 3,
                      right: 3,
                      child: _StarsBadge(stars: lesson.starsEarned),
                    ),
                  // Lesson number badge (bottom-right)
                  Positioned(
                    bottom: 3,
                    right: 3,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceLight.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        '${lesson.lessonNumber}',
                        style: TextStyle(
                          color: AppColors.textDark,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
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

  Widget _nodeIcon(LessonProgressModel lesson) {
    if (lesson.isLocked) {
      return Icon(Icons.lock_rounded, size: 26, color: AppColors.grey500);
    }
    if (lesson.isCompleted) {
      return Icon(Icons.check_rounded, size: 34, color: AppColors.surfaceLight);
    }
    if (lesson.isCurrent) {
      return Icon(
        Icons.play_arrow_rounded,
        size: 36,
        color: AppColors.surfaceLight,
      );
    }
    return Icon(
      _lessonTypeIcon(lesson.title),
      size: 28,
      color: AppColors.surfaceLight,
    );
  }

  IconData _lessonTypeIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('quiz') || t.contains('test') || t.contains('mock')) {
      return Icons.emoji_events_rounded;
    }
    if (t.contains('listen') || t.contains('audio')) {
      return Icons.headphones_rounded;
    }
    if (t.contains('speak') || t.contains('pronun')) return Icons.mic_rounded;
    if (t.contains('read') || t.contains('passage')) {
      return Icons.menu_book_rounded;
    }
    if (t.contains('writ') || t.contains('essay') || t.contains('task')) {
      return Icons.edit_note_rounded;
    }
    if (t.contains('grammar') || t.contains('tense') || t.contains('verb')) {
      return Icons.auto_stories_rounded;
    }
    if (t.contains('vocab') || t.contains('word')) {
      return Icons.translate_rounded;
    }
    return Icons.school_rounded;
  }
}

// ─────────────────────────────────────────────────────────────
// Stars badge
// ─────────────────────────────────────────────────────────────

class _StarsBadge extends StatelessWidget {
  final int stars;
  const _StarsBadge({required this.stars});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black26, blurRadius: 3, offset: Offset(0, 1)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.star_rounded,
            size: 9,
            color: Theme.of(context).colorScheme.surface,
          ),
          Text(
            '$stars',
            style: TextStyle(
              fontSize: 9,
              color: Theme.of(context).colorScheme.surface,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Current lesson label (speech bubble above active node)
// ─────────────────────────────────────────────────────────────

class _CurrentLessonLabel extends StatelessWidget {
  final LessonProgressModel lesson;
  final Color color;
  const _CurrentLessonLabel({required this.lesson, required this.color});

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      duration: const Duration(milliseconds: 600),
      tween: Tween(begin: 0.0, end: 1.0),
      curve: Curves.elasticOut,
      builder: (_, v, child) => Transform.scale(scale: v, child: child),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.35),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Text(
              lesson.title.length > 28
                  ? '${lesson.title.substring(0, 26)}…'
                  : lesson.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.surface,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
          ),
          // Triangle pointer
          ClipPath(
            clipper: _TriangleClipper(),
            child: Container(width: 14, height: 8, color: color),
          ),
        ],
      ),
    );
  }
}

class _TriangleClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width / 2, size.height)
    ..lineTo(size.width, 0)
    ..close();

  @override
  bool shouldReclip(_) => false;
}

// ─────────────────────────────────────────────────────────────
// Unit chapter banner
// ─────────────────────────────────────────────────────────────

class _UnitBanner extends StatelessWidget {
  final UnitRoadmapModel unit;
  const _UnitBanner({required this.unit});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = _mixWithWhite(
      _parseHex(unit.backgroundColor),
      isDark ? 0.30 : 0.14,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.75)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.35),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 0, sigmaY: 0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            child: Row(
              children: [
                // Unit number chip
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight.withValues(alpha: 0.32),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${unit.unitNumber}',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textDark,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                // Title & description
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        unit.title,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.surface,
                          height: 1.2,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (unit.description != null) ...[
                        SizedBox(height: 2),
                        Text(
                          unit.description!,
                          style: TextStyle(
                            fontSize: 11,
                            color: Theme.of(
                              context,
                            ).colorScheme.surface.withValues(alpha: 0.8),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                // Progress ring
                _UnitProgressRing(unit: unit),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitProgressRing extends StatelessWidget {
  final UnitRoadmapModel unit;
  const _UnitProgressRing({required this.unit});

  @override
  Widget build(BuildContext context) {
    final pct = unit.completionPercentage / 100;
    return SizedBox(
      width: 48,
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          TweenAnimationBuilder<double>(
            duration: Duration(milliseconds: 900),
            tween: Tween(begin: 0, end: pct),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => CircularProgressIndicator(
              value: v,
              strokeWidth: 5,
              backgroundColor: Theme.of(
                context,
              ).colorScheme.surface.withValues(alpha: 0.25),
              valueColor: const AlwaysStoppedAnimation(Colors.white),
              strokeCap: StrokeCap.round,
            ),
          ),
          Text(
            '${unit.completedLessons}/${unit.totalLessons}',
            style: TextStyle(
              color: Theme.of(context).colorScheme.surface,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Lesson detail bottom sheet
// ─────────────────────────────────────────────────────────────

class _LessonDetailSheet extends StatelessWidget {
  final _NodeLayout layout;
  final String courseId;
  const _LessonDetailSheet({required this.layout, required this.courseId});

  @override
  Widget build(BuildContext context) {
    final lesson = layout.lesson;
    final color = layout.baseColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkElevated : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, -8),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            decoration: BoxDecoration(
              color: Colors.grey.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Icon circle
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3), width: 2),
            ),
            child: Icon(_typeIcon(lesson.title), size: 32, color: color),
          ),
          const SizedBox(height: 14),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              lesson.title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
                height: 1.2,
              ),
            ),
          ),
          if (lesson.description != null) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Text(
                lesson.description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.grey600,
                  height: 1.4,
                ),
              ),
            ),
          ],
          const SizedBox(height: 20),
          // Stats row
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (lesson.bestScore != null)
                _StatChip(
                  icon: Icons.emoji_events_rounded,
                  label: '${lesson.bestScore!.toStringAsFixed(0)}%',
                  color: AppColors.warning,
                ),
              if (lesson.starsEarned > 0) ...[
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.star_rounded,
                  label: '${lesson.starsEarned}/3',
                  color: AppColors.orange,
                ),
              ],
              if (lesson.attemptsCount > 0) ...[
                const SizedBox(width: 10),
                _StatChip(
                  icon: Icons.replay_rounded,
                  label: '${lesson.attemptsCount}×',
                  color: Colors.blueGrey,
                ),
              ],
            ],
          ),
          const SizedBox(height: 24),
          // CTA button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: _CtaButton(lesson: lesson, color: color, courseId: courseId),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  IconData _typeIcon(String title) {
    final t = title.toLowerCase();
    if (t.contains('quiz') || t.contains('test') || t.contains('mock')) {
      return Icons.emoji_events_rounded;
    }
    if (t.contains('listen')) return Icons.headphones_rounded;
    if (t.contains('speak') || t.contains('pronun')) return Icons.mic_rounded;
    if (t.contains('read')) return Icons.menu_book_rounded;
    if (t.contains('writ') || t.contains('task') || t.contains('essay')) {
      return Icons.edit_note_rounded;
    }
    if (t.contains('grammar') || t.contains('tense') || t.contains('verb')) {
      return Icons.auto_stories_rounded;
    }
    if (t.contains('vocab') || t.contains('word')) {
      return Icons.translate_rounded;
    }
    return Icons.school_rounded;
  }
}

class _StatChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  const _StatChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CtaButton extends StatelessWidget {
  final LessonProgressModel lesson;
  final Color color;
  final String courseId;
  const _CtaButton({
    required this.lesson,
    required this.color,
    required this.courseId,
  });

  @override
  Widget build(BuildContext context) {
    final label = lesson.isCompleted
        ? 'Practice Again'
        : lesson.isCurrent
        ? 'Continue'
        : 'Start Lesson';
    final icon = lesson.isCompleted
        ? Icons.replay_rounded
        : Icons.play_arrow_rounded;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [color, color.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.4),
              blurRadius: 14,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.transparent,
            shadowColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            foregroundColor: Colors.white,
          ),
          icon: Icon(icon),
          label: Text(
            label,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          onPressed: () {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => LearningSessionScreen(
                  lessonId: lesson.lessonId,
                  courseId: courseId,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Error / empty states
// ─────────────────────────────────────────────────────────────

class _ErrorView extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: Colors.redAccent,
            ),
            const SizedBox(height: 16),
            Text(
              'Failed to load roadmap',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.grey600),
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.school_outlined, size: 72, color: AppColors.grey400),
          const SizedBox(height: 20),
          Text(
            'No lessons available',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Check back later for new content',
            style: TextStyle(color: AppColors.grey500),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

Color _parseHex(String hex) {
  try {
    final clean = hex.replaceFirst('#', '');
    return Color(int.parse('FF$clean', radix: 16));
  } catch (_) {
    return AppColors.primary;
  }
}

Color _mixWithWhite(Color color, double amount) {
  final t = amount.clamp(0.0, 1.0);
  return Color.lerp(color, AppColors.surfaceLight, t) ?? color;
}

Color _ensureRoadmapContrast(Color color) {
  final luminance = color.computeLuminance();
  if (luminance >= 0.34) {
    return color;
  }
  final boosted = Color.lerp(color, AppColors.roadmapNodeFallbackDark, 0.42);
  return boosted ?? color;
}
