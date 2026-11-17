import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/admin_colors.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import '../data/curriculum_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class CourseDetailScreen extends StatefulWidget {
  final String courseId;
  const CourseDetailScreen({super.key, required this.courseId});

  @override
  State<CourseDetailScreen> createState() => _CourseDetailScreenState();
}

class _CourseDetailScreenState extends State<CourseDetailScreen> {
  final _repo = CurriculumRepository();
  List<Unit> _units = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final units = await _repo.getUnits(widget.courseId);
      if (mounted) {
        setState(() {
          _units = units;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load units.';
        });
      }
    }
  }

  Future<void> _edit([Unit? unit]) async {
    final title = TextEditingController(text: unit?.title);
    final description = TextEditingController(text: unit?.description);
    final order = TextEditingController(
      text: '${unit?.orderIndex ?? _units.length}',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(unit == null ? 'Create unit' : 'Edit unit'),
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
                maxLines: 2,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: order,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Order'),
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
    );
    if (saved != true) return;
    final data = {
      'title': title.text.trim(),
      'description': description.text.trim(),
      'order_index': int.tryParse(order.text) ?? _units.length,
    };
    try {
      if (unit == null) {
        await _repo.createUnit({...data, 'course_id': widget.courseId});
      } else {
        await _repo.updateUnit(unit.id, data);
      }
      await _load();
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not save unit.');
    }
  }

  Future<void> _delete(Unit unit) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete unit?'),
        content: Text('Delete “${unit.title}”?'),
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
    if (ok == true) {
      try {
        await _repo.deleteUnit(unit.id);
        await _load();
      } catch (_) {
        if (mounted) setState(() => _error = 'Could not delete unit.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AdminColors.background,
              elevation: 0,
              leading: AppBackButton(
                icon: Icons.arrow_back,
                color: AdminColors.onSurface,
                onPressed: () => context.pop(),
              ),
              actions: [
                FilledButton.icon(
                  onPressed: _edit,
                  icon: const Icon(Icons.add, size: 16),
                  label: Text(
                    'NEW UNIT',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.05,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: 8,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
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
                    'Course Detail',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                      letterSpacing: -0.02,
                    ),
                  ),
                  const SizedBox(height: 20),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.5,
                    children: [
                      _MiniStat(
                        label: 'Units',
                        value: '${_units.length}',
                        icon: Icons.layers_outlined,
                      ),
                      _MiniStat(
                        label: 'Lessons',
                        value:
                            '${_units.fold<int>(0, (sum, unit) => sum + unit.lessonCount)}',
                        icon: Icons.book_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  Text(
                    'Unit Structure',
                    style: Theme.of(context).textTheme.sectionTitle?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: AdminColors.error,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(
                            child: Text(
                              _error!,
                              style: GoogleFonts.spaceGrotesk(
                                color: AdminColors.error,
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: _load,
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    ),
                  if (_loading)
                    const Column(
                      children: [
                        SkeletonBox(height: 92),
                        SizedBox(height: 10),
                        SkeletonBox(height: 92),
                      ],
                    )
                  else if (_units.isEmpty)
                    Center(
                      child: Text(
                        'No units yet',
                        style: GoogleFonts.spaceGrotesk(
                          color: AdminColors.onSurfaceMuted,
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _units.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) {
                        final unit = _units[i];
                        final isFirst = i == 0;
                        return _UnitCard(
                          unit: unit,
                          isExpanded: isFirst,
                          onTap: () => context.push(
                            '/curriculum/units',
                            extra: {'unitId': unit.id, 'unitTitle': unit.title},
                          ),
                          onEdit: () => _edit(unit),
                          onDelete: () => _delete(unit),
                        );
                      },
                    ),
                ]),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AdminColors.primaryBright,
        onPressed: _edit,
        child: Icon(Icons.add, color: Theme.of(context).colorScheme.onPrimary),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AdminColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(icon, color: AdminColors.primary, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 0.06,
              color: AdminColors.onSurfaceMuted,
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: AdminColors.onSurface,
              letterSpacing: -0.02,
            ),
          ),
        ],
      ),
    );
  }
}

class _UnitCard extends StatelessWidget {
  final Unit unit;
  final bool isExpanded;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _UnitCard({
    required this.unit,
    this.isExpanded = false,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AdminColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: isExpanded
                ? AdminColors.primary
                : AdminColors.outlineVariant,
            width: isExpanded ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'UNIT ${(unit.orderIndex + 1).toString().padLeft(2, '0')}',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AdminColors.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    unit.title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(
                        Icons.book_outlined,
                        size: 12,
                        color: AdminColors.onSurfaceMuted,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        '${unit.lessonCount} Lessons',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: AdminColors.onSurfaceMuted,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) => v == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'edit', child: Text('Edit')),
                PopupMenuItem(value: 'delete', child: Text('Delete')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
