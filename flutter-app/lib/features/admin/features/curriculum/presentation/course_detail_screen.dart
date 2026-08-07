import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/curriculum_repository.dart';

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
    setState(() { _loading = true; _error = null; });
    try {
      final units = await _repo.getUnits(widget.courseId);
      if (mounted) setState(() { _units = units; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Could not load units.'; });
    }
  }

  Future<void> _edit([Unit? unit]) async {
    final title = TextEditingController(text: unit?.title);
    final description = TextEditingController(text: unit?.description);
    final order = TextEditingController(text: '${unit?.orderIndex ?? _units.length}');
    final saved = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text(unit == null ? 'Create unit' : 'Edit unit'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        TextField(controller: title, autofocus: true, decoration: const InputDecoration(labelText: 'Title *')),
        TextField(controller: description, maxLines: 2, decoration: const InputDecoration(labelText: 'Description')),
        TextField(controller: order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order')),
      ])), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, title.text.trim().isNotEmpty), child: const Text('Save'))]));
    if (saved != true) return;
    final data = {'title': title.text.trim(), 'description': description.text.trim(), 'order_index': int.tryParse(order.text) ?? _units.length};
    try { if (unit == null) { await _repo.createUnit({...data, 'course_id': widget.courseId}); } else { await _repo.updateUnit(unit.id, data); } await _load(); }
    catch (_) { if (mounted) setState(() => _error = 'Could not save unit.'); }
  }

  Future<void> _delete(Unit unit) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('Delete unit?'), content: Text('Delete “${unit.title}”?'), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))]));
    if (ok == true) { try { await _repo.deleteUnit(unit.id); await _load(); } catch (_) { if (mounted) setState(() => _error = 'Could not delete unit.'); } }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: RefreshIndicator(onRefresh: _load, child: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            leading: AppBackButton(
              icon: Icons.arrow_back,
              color: AppColors.onSurface,
              onPressed: () => context.pop(),
            ),
            actions: [
              ElevatedButton.icon(
                onPressed: _edit,
                icon: const Icon(Icons.add, size: 16),
                label: Text('NEW UNIT',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.05)),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
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
                  'Course Detail',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
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
                    _MiniStat(label: 'Units', value: '${_units.length}', icon: Icons.layers_outlined),
                    _MiniStat(label: 'Lessons', value: '${_units.fold<int>(0, (sum, unit) => sum + unit.lessonCount)}', icon: Icons.book_outlined),
                  ],
                ),
                const SizedBox(height: 24),
                Text(
                  'Unit Structure',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                  ),
                ),
                const SizedBox(height: 12),
                if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Row(children: [const Icon(Icons.error_outline, color: AppColors.error), const SizedBox(width: 8), Expanded(child: Text(_error!, style: GoogleFonts.spaceGrotesk(color: AppColors.error))), TextButton(onPressed: _load, child: const Text('Retry'))])),
                if (_loading)
                  const Column(children: [AdminSkeleton(height: 92), SizedBox(height: 10), AdminSkeleton(height: 92)])
                else if (_units.isEmpty)
                  Center(
                    child: Text('No units yet',
                        style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
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
        backgroundColor: AppColors.primaryBright,
        onPressed: _edit,
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _MiniStat({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
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
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: AppColors.primary, size: 15),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.06,
                  color: AppColors.onSurfaceMuted)),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w700, color: AppColors.onSurface,
                  letterSpacing: -0.02)),
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

  const _UnitCard({required this.unit, this.isExpanded = false, required this.onTap, required this.onEdit, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? AppColors.primary : AppColors.outlineVariant,
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
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.08,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    unit.title,
                    style: GoogleFonts.spaceGrotesk(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      const Icon(Icons.book_outlined, size: 12, color: AppColors.onSurfaceMuted),
                      const SizedBox(width: 4),
                      Text(
                        '${unit.lessonCount} Lessons',
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 11, color: AppColors.onSurfaceMuted),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(onSelected: (v) => v == 'edit' ? onEdit() : onDelete(), itemBuilder: (_) => const [PopupMenuItem(value: 'edit', child: Text('Edit')), PopupMenuItem(value: 'delete', child: Text('Delete'))]),
          ],
        ),
      ),
    );
  }
}
