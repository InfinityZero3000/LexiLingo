import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import '../data/curriculum_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class CurriculumScreen extends StatefulWidget {
  const CurriculumScreen({super.key});

  @override
  State<CurriculumScreen> createState() => _CurriculumScreenState();
}

class _CurriculumScreenState extends State<CurriculumScreen> {
  final _repo = CurriculumRepository();
  List<Course> _courses = [];
  bool _loading = true;
  String? _error;
  final _searchCtrl = TextEditingController();
  String? _level;
  bool? _published;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String? search]) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final courses = await _repo.getCourses(
        search: search,
        level: _level,
        isPublished: _published,
      );
      if (mounted) {
        setState(() {
          _courses = courses;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không thể tải danh sách courses.';
        });
      }
    }
  }

  Future<void> _edit([Course? course]) async {
    final title = TextEditingController(text: course?.title);
    final description = TextEditingController(text: course?.description);
    final language = TextEditingController(text: course?.language ?? 'en');
    final tags = TextEditingController(text: course?.tags.join(', '));
    final thumbnail = TextEditingController(text: course?.thumbnailUrl);
    var level = course?.level ?? 'A1';
    var published = course?.isPublished ?? false;
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(course == null ? 'Create course' : 'Edit course'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: true,
                  decoration: const InputDecoration(labelText: 'Title *'),
                ),
                TextField(
                  controller: description,
                  maxLines: 3,
                  decoration: const InputDecoration(labelText: 'Description'),
                ),
                TextField(
                  controller: language,
                  decoration: const InputDecoration(labelText: 'Language *'),
                ),
                TextField(
                  controller: tags,
                  decoration: const InputDecoration(
                    labelText: 'Tags (comma separated)',
                  ),
                ),
                TextField(
                  controller: thumbnail,
                  decoration: const InputDecoration(labelText: 'Thumbnail URL'),
                ),
                DropdownButtonFormField<String>(
                  initialValue: level,
                  decoration: const InputDecoration(labelText: 'Level'),
                  items: ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
                      .map((v) => DropdownMenuItem(value: v, child: Text(v)))
                      .toList(),
                  onChanged: (v) => level = v!,
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Published'),
                  value: published,
                  onChanged: (v) => setDialogState(() => published = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              style: TextButton.styleFrom(
                minimumSize: const Size(kMinTapTarget, kMinTapTarget),
              ),
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(context, title.text.trim().isNotEmpty),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true) return;
    final data = {
      'title': title.text.trim(),
      'description': description.text.trim(),
      'language': language.text.trim(),
      'level': level,
      'tags': tags.text
          .split(',')
          .map((v) => v.trim())
          .where((v) => v.isNotEmpty)
          .toList(),
      'thumbnail_url': thumbnail.text.trim(),
      'is_published': published,
    };
    try {
      if (course == null) {
        await _repo.createCourse(data);
      } else {
        await _repo.updateCourse(course.id, data);
      }
      await _load(_searchCtrl.text.trim());
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save course.');
    }
  }

  Future<void> _delete(Course course) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete course?'),
        content: Text('Delete “${course.title}”?'),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _repo.deleteCourse(course.id);
      await _load(_searchCtrl.text.trim());
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not delete course.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: RefreshIndicator(
        onRefresh: () => _load(_searchCtrl.text.trim()),
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AdminColors.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: AdminColors.onSurface,
                ),
                onPressed: AdminShell.openDrawer,
              ),
              title: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: AdminColors.primary,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      Icons.language,
                      color: Theme.of(context).colorScheme.onPrimary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    'LingoAdmin',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.primary,
                    ),
                  ),
                ],
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  // breadcrumb
                  Text(
                    'CURRICULUM MANAGEMENT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AdminColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Curriculum Overview',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                      letterSpacing: -0.02,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'Manage global language tracks, optimize learning paths across all courses.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AdminColors.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _SmallStat(
                          label: 'COURSES SHOWN',
                          value: '${_courses.length}',
                          icon: Icons.menu_book_outlined,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _SmallStat(
                          label: 'PUBLISHED',
                          value:
                              '${_courses.where((c) => c.isPublished).length}',
                          icon: Icons.public,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AdminColors.errorContainer,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AdminColors.error,
                            size: 18,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: AdminColors.error),
                            ),
                          ),
                          GestureDetector(
                            onTap: () => _load(),
                            child: Text(
                              'Retry',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AdminColors.error,
                                  ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  // Create new course button
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _edit,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(
                        '+ Create New Course',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  // Search
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'Search courses...',
                      prefixIcon: const Icon(
                        Icons.search,
                        color: AdminColors.onSurfaceMuted,
                      ),
                      suffixIcon: IconButton(
                        icon: const Icon(
                          Icons.close,
                          color: AdminColors.onSurfaceMuted,
                        ),
                        onPressed: () {
                          _searchCtrl.clear();
                          _load();
                        },
                      ),
                    ),
                    onSubmitted: _load,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Wrap(
                    spacing: 8,
                    children: [
                      DropdownButton<String?>(
                        value: _level,
                        hint: const Text('All levels'),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('All levels'),
                          ),
                          ...['A1', 'A2', 'B1', 'B2', 'C1', 'C2'].map(
                            (v) => DropdownMenuItem(value: v, child: Text(v)),
                          ),
                        ],
                        onChanged: (v) {
                          setState(() => _level = v);
                          _load(_searchCtrl.text.trim());
                        },
                      ),
                      DropdownButton<bool?>(
                        value: _published,
                        hint: const Text('All statuses'),
                        items: const [
                          DropdownMenuItem(
                            value: null,
                            child: Text('All statuses'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Published'),
                          ),
                          DropdownMenuItem(value: false, child: Text('Draft')),
                        ],
                        onChanged: (v) {
                          setState(() => _published = v);
                          _load(_searchCtrl.text.trim());
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Top Performing Courses',
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_loading)
                    const Column(
                      children: [
                        SkeletonBox(height: 150),
                        SizedBox(height: AppSpacing.md),
                        SkeletonBox(height: 150),
                      ],
                    )
                  else if (_courses.isEmpty)
                    Center(
                      child: Text(
                        'No courses found',
                        style: GoogleFonts.spaceGrotesk(
                          color: AdminColors.onSurfaceMuted,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _courses.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppSpacing.md),
                      itemBuilder: (_, i) => _CourseCard(
                        course: _courses[i],
                        onTap: () => context.push(
                          '/curriculum/course/${_courses[i].id}',
                        ),
                        onEdit: () => _edit(_courses[i]),
                        onDelete: () => _delete(_courses[i]),
                        onPublish: () async {
                          final c = _courses[i];
                          c.isPublished
                              ? await _repo.unpublishCourse(c.id)
                              : await _repo.publishCourse(c.id);
                          await _load(_searchCtrl.text.trim());
                        },
                      ),
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SmallStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _SmallStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AdminColors.primary, size: 20),
          const SizedBox(height: AppSpacing.sm),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: AdminColors.onSurface,
              letterSpacing: -0.02,
            ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.08,
              color: AdminColors.onSurfaceMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _CourseCard extends StatelessWidget {
  final Course course;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onPublish;

  const _CourseCard({
    required this.course,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onPublish,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (course.thumbnailUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
                child: Image.network(
                  course.thumbnailUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: AdminColors.surfaceContainerHigh,
                    child: const Center(
                      child: Icon(
                        Icons.image_outlined,
                        color: AdminColors.onSurfaceMuted,
                      ),
                    ),
                  ),
                ),
              )
            else
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AdminColors.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: Center(
                  child: Icon(
                    Icons.menu_book,
                    color: AdminColors.primary,
                    size: 32,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _LevelBadge(level: course.level),
                      const Spacer(),
                      PopupMenuButton<String>(
                        onSelected: (v) {
                          if (v == 'edit') onEdit();
                          if (v == 'publish') onPublish();
                          if (v == 'delete') onDelete();
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Text('Edit'),
                          ),
                          PopupMenuItem(
                            value: 'publish',
                            child: Text(
                              course.isPublished ? 'Unpublish' : 'Publish',
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text('Delete'),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.sm,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: course.isPublished
                              ? AdminColors.successContainer
                              : AdminColors.warningContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          course.isPublished ? 'LIVE' : 'DRAFT',
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.05,
                                color: course.isPublished
                                    ? AdminColors.success
                                    : AdminColors.warning,
                              ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    course.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                    ),
                  ),
                  if (course.description != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      course.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AdminColors.onSurfaceMuted,
                      ),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      _InfoChip(
                        icon: Icons.view_module_outlined,
                        label: '${course.unitCount} units enrolled',
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${course.lessonCount} LESSONS · ${course.totalXp} XP',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: AdminColors.onSurfaceMuted,
                                  ),
                            ),
                            const SizedBox(height: AppSpacing.xs),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: course.isPublished ? 1 : 0,
                                backgroundColor:
                                    AdminColors.surfaceContainerHigh,
                                valueColor: const AlwaysStoppedAnimation(
                                  AdminColors.primary,
                                ),
                                minHeight: 5,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Icon(
                        Icons.chevron_right,
                        color: AdminColors.onSurfaceMuted,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LevelBadge extends StatelessWidget {
  final String level;
  const _LevelBadge({required this.level});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: AdminColors.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          color: AdminColors.primary,
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: AdminColors.onSurfaceMuted),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: AdminColors.onSurfaceMuted),
        ),
      ],
    );
  }
}
