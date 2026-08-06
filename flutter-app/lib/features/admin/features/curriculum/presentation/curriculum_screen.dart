import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/curriculum_repository.dart';

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
    setState(() { _loading = true; _error = null; });
    try {
      final courses = await _repo.getCourses(search: search, level: _level, isPublished: _published);
      if (mounted) {
        setState(() {
          _courses = courses;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Không thể tải danh sách courses.'; });
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
    final saved = await showDialog<bool>(context: context, builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(course == null ? 'Create course' : 'Edit course'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Title *')),
          TextField(controller: description, maxLines: 3, decoration: const InputDecoration(labelText: 'Description')),
          TextField(controller: language, decoration: const InputDecoration(labelText: 'Language *')),
          TextField(controller: tags, decoration: const InputDecoration(labelText: 'Tags (comma separated)')),
          TextField(controller: thumbnail, decoration: const InputDecoration(labelText: 'Thumbnail URL')),
          DropdownButtonFormField<String>(initialValue: level, decoration: const InputDecoration(labelText: 'Level'),
            items: ['A1','A2','B1','B2','C1','C2'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
            onChanged: (v) => level = v!),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Published'), value: published,
            onChanged: (v) => setDialogState(() => published = v)),
        ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, title.text.trim().isNotEmpty), child: const Text('Save'))],
      ),
    ));
    if (saved != true) return;
    final data = {'title': title.text.trim(), 'description': description.text.trim(), 'language': language.text.trim(), 'level': level, 'tags': tags.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList(), 'thumbnail_url': thumbnail.text.trim(), 'is_published': published};
    try {
      if (course == null) { await _repo.createCourse(data); } else { await _repo.updateCourse(course.id, data); }
      await _load(_searchCtrl.text.trim());
    } catch (_) { if (mounted) setState(() => _error = 'Could not save course.'); }
  }

  Future<void> _delete(Course course) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete course?'),
      content: Text('Delete “${course.title}”?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (ok != true) return;
    try { await _repo.deleteCourse(course.id); await _load(_searchCtrl.text.trim()); }
    catch (_) { if (mounted) setState(() => _error = 'Could not delete course.'); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(onRefresh: () => _load(_searchCtrl.text.trim()), child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
              onPressed: AdminShell.openDrawer,
            ),
            title: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Icon(Icons.language, color: Colors.white, size: 16),
                ),
                const SizedBox(width: 8),
                Text('LingoAdmin',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.onSurface),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // breadcrumb
                Text(
                  'CURRICULUM MANAGEMENT',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.08,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Curriculum Overview',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Manage global language tracks, optimize learning paths across all courses.',
                  style: GoogleFonts.spaceGrotesk(
                      fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(
                    child: _SmallStat(
                      label: 'COURSES SHOWN',
                      value: '${_courses.length}',
                      icon: Icons.menu_book_outlined,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SmallStat(
                      label: 'PUBLISHED',
                      value: '${_courses.where((c) => c.isPublished).length}',
                      icon: Icons.public,
                    ),
                  ),
                ]),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.error)),
                        ),
                        GestureDetector(
                          onTap: () => _load(),
                          child: Text('Retry',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Create new course button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _edit,
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      '+ Create New Course',
                      style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                // Search
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search courses...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceMuted),
                    suffixIcon: IconButton(icon: const Icon(Icons.close, color: AppColors.onSurfaceMuted), onPressed: () { _searchCtrl.clear(); _load(); }),
                  ),
                  onSubmitted: _load,
                ),
                const SizedBox(height: 16),
                Wrap(spacing: 8, children: [
                  DropdownButton<String?>(value: _level, hint: const Text('All levels'), items: [const DropdownMenuItem(value: null, child: Text('All levels')), ...['A1','A2','B1','B2','C1','C2'].map((v) => DropdownMenuItem(value: v, child: Text(v)))], onChanged: (v) { setState(() => _level = v); _load(_searchCtrl.text.trim()); }),
                  DropdownButton<bool?>(value: _published, hint: const Text('All statuses'), items: const [DropdownMenuItem(value: null, child: Text('All statuses')), DropdownMenuItem(value: true, child: Text('Published')), DropdownMenuItem(value: false, child: Text('Draft'))], onChanged: (v) { setState(() => _published = v); _load(_searchCtrl.text.trim()); }),
                ]),
                const SizedBox(height: 8),
                Text(
                  'Top Performing Courses',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                if (_loading)
                  const Column(children: [AdminSkeleton(height: 150), SizedBox(height: 12), AdminSkeleton(height: 150)])
                else if (_courses.isEmpty)
                  Center(
                    child: Text('No courses found',
                        style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: _courses.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) => _CourseCard(
                      course: _courses[i],
                      onTap: () => context.push('/curriculum/course/${_courses[i].id}'),
                      onEdit: () => _edit(_courses[i]),
                      onDelete: () => _delete(_courses[i]),
                      onPublish: () async { final c = _courses[i]; c.isPublished ? await _repo.unpublishCourse(c.id) : await _repo.publishCourse(c.id); await _load(_searchCtrl.text.trim()); },
                    ),
                  ),
              ]),
            ),
          ),
        ],
      )),
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
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(height: 8),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: AppColors.onSurface,
                  letterSpacing: -0.02)),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.08,
                  color: AppColors.onSurfaceMuted)),
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

  const _CourseCard({required this.course, required this.onTap, required this.onEdit, required this.onDelete, required this.onPublish});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outlineVariant, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (course.thumbnailUrl != null)
              ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                child: Image.network(
                  course.thumbnailUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 120,
                    color: AppColors.surfaceContainerHigh,
                    child: const Center(child: Icon(Icons.image_outlined, color: AppColors.onSurfaceMuted)),
                  ),
                ),
              )
            else
              Container(
                height: 80,
                decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Center(
                  child: Icon(Icons.menu_book, color: AppColors.primary, size: 32),
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
                      PopupMenuButton<String>(onSelected: (v) { if (v == 'edit') onEdit(); if (v == 'publish') onPublish(); if (v == 'delete') onDelete(); },
                        itemBuilder: (_) => [const PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'publish', child: Text(course.isPublished ? 'Unpublish' : 'Publish')), const PopupMenuItem(value: 'delete', child: Text('Delete'))]),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: course.isPublished
                              ? AppColors.successContainer
                              : AppColors.warningContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          course.isPublished ? 'LIVE' : 'DRAFT',
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.05,
                            color: course.isPublished ? AppColors.success : AppColors.warning,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    course.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  if (course.description != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      course.description!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.spaceGrotesk(
                          fontSize: 12, color: AppColors.onSurfaceMuted),
                    ),
                  ],
                  const SizedBox(height: 12),
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
                            Text('${course.lessonCount} LESSONS · ${course.totalXp} XP',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.onSurfaceMuted)),
                            const SizedBox(height: 4),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(value: course.isPublished ? 1 : 0, backgroundColor: AppColors.surfaceContainerHigh, valueColor: const AlwaysStoppedAnimation(AppColors.primary), minHeight: 5),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Icon(Icons.chevron_right, color: AppColors.onSurfaceMuted),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.primaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        level,
        style: GoogleFonts.spaceGrotesk(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: AppColors.primary,
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
        Icon(icon, size: 13, color: AppColors.onSurfaceMuted),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
      ],
    );
  }
}
