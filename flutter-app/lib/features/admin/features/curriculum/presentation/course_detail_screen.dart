import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/app_colors.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final units = await _repo.getUnits(widget.courseId);
      if (mounted) setState(() { _units = units; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
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
                onPressed: () {},
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
                // Stats row
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 1.5,
                  children: [
                    _MiniStat(label: 'Units', value: '${_units.length}', icon: Icons.layers_outlined),
                    _MiniStat(label: 'Active Lessons', value: '148', icon: Icons.book_outlined),
                    _MiniStat(label: 'Completion Rate', value: '84%', icon: Icons.check_circle_outline),
                    _MiniStat(label: 'Active Students', value: '1.2k', icon: Icons.people_outline),
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
                if (_loading)
                  const Center(child: CircularProgressIndicator(color: AppColors.primary))
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
                      );
                    },
                  ),
                const SizedBox(height: 24),
                // Insights dark card
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.navy,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Curriculum Insights',
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: Colors.white)),
                      const SizedBox(height: 6),
                      Text(
                        'Drop-offs increased 15%. Review quiz difficulty.',
                        style: GoogleFonts.spaceGrotesk(fontSize: 13, color: Colors.white60),
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => context.push('/settings/analytics'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primaryBright,
                        ),
                        child: Text(
                          'VIEW ANALYTICS',
                          style: GoogleFonts.spaceGrotesk(
                              fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 0.05),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryBright,
        onPressed: () {},
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

  const _UnitCard({required this.unit, this.isExpanded = false, required this.onTap});

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
            Icon(
              isExpanded ? Icons.drag_indicator : Icons.lock_outline,
              color: isExpanded ? AppColors.onSurfaceMuted : AppColors.outlineVariant,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}
