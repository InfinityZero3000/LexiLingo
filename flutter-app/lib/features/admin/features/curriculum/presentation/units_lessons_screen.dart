import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/app_colors.dart';
import '../data/curriculum_repository.dart';

class UnitsLessonsScreen extends StatefulWidget {
  final String unitId;
  final String unitTitle;

  const UnitsLessonsScreen({
    super.key,
    required this.unitId,
    required this.unitTitle,
  });

  @override
  State<UnitsLessonsScreen> createState() => _UnitsLessonsScreenState();
}

class _UnitsLessonsScreenState extends State<UnitsLessonsScreen> {
  final _repo = CurriculumRepository();
  List<Lesson> _lessons = [];
  bool _loading = true;
  String? _expandedId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final lessons = await _repo.getLessons(widget.unitId);
      if (mounted) setState(() { _lessons = lessons; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          'Lessons in ${widget.unitTitle}',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16),
        ),
        leading: AppBackButton(
          icon: Icons.arrow_back,
          color: AppColors.onSurface,
          onPressed: () => context.pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.swap_vert, size: 16, color: AppColors.onSurfaceMuted),
            label: Text('REORDER',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.onSurfaceMuted)),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(20),
                    itemCount: _lessons.length + 1,
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (_, i) {
                      if (i == _lessons.length) {
                        return GestureDetector(
                          onTap: () {},
                          child: Container(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            decoration: BoxDecoration(
                              border: Border.all(
                                  color: AppColors.outlineVariant, width: 1.5, style: BorderStyle.solid),
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Center(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.add, size: 16, color: AppColors.onSurfaceMuted),
                                  const SizedBox(width: 6),
                                  Text('ADD NEW LESSON',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.05,
                                          color: AppColors.onSurfaceMuted)),
                                ],
                              ),
                            ),
                          ),
                        );
                      }
                      final lesson = _lessons[i];
                      final isExpanded = _expandedId == lesson.id;
                      return _LessonCard(
                        lesson: lesson,
                        index: i + 1,
                        isExpanded: isExpanded,
                        onTap: () => setState(() {
                          _expandedId = isExpanded ? null : lesson.id;
                        }),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final Lesson lesson;
  final int index;
  final bool isExpanded;
  final VoidCallback onTap;

  const _LessonCard({
    required this.lesson,
    required this.index,
    required this.isExpanded,
    required this.onTap,
  });

  Color get _statusColor {
    switch (lesson.status.toLowerCase()) {
      case 'live':
        return AppColors.success;
      case 'editing':
        return AppColors.warning;
      case 'draft':
        return AppColors.onSurfaceMuted;
      default:
        return AppColors.onSurfaceMuted;
    }
  }

  Color get _statusBg {
    switch (lesson.status.toLowerCase()) {
      case 'live':
        return AppColors.successContainer;
      case 'editing':
        return AppColors.warningContainer;
      case 'draft':
        return AppColors.surfaceContainerHigh;
      default:
        return AppColors.surfaceContainerHigh;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isExpanded ? AppColors.primary : AppColors.outlineVariant,
            width: isExpanded ? 1.5 : 0.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: isExpanded ? AppColors.primary : AppColors.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '$index.${lesson.orderIndex}',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: isExpanded ? Colors.white : AppColors.primary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.title,
                          style: GoogleFonts.spaceGrotesk(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.onSurface,
                          ),
                        ),
                        if (lesson.description != null)
                          Text(
                            lesson.description!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 12, color: AppColors.onSurfaceMuted),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _statusBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      lesson.status.toUpperCase(),
                      style: GoogleFonts.spaceGrotesk(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: _statusColor,
                        letterSpacing: 0.05,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isExpanded)
                    Icon(Icons.keyboard_arrow_up,
                        color: AppColors.onSurfaceMuted, size: 20)
                  else
                    Row(
                      children: [
                        Icon(Icons.edit_outlined,
                            color: AppColors.onSurfaceMuted, size: 18),
                        const SizedBox(width: 8),
                        Icon(Icons.delete_outline,
                            color: AppColors.onSurfaceMuted, size: 18),
                      ],
                    ),
                ],
              ),
            ),
            if (isExpanded) ...[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('CONTENT MODULES',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
                              const SizedBox(height: 8),
                              _ModuleRow(icon: Icons.play_circle_outline, label: 'Intro Video (8:45)'),
                              const SizedBox(height: 6),
                              _ModuleRow(icon: Icons.description_outlined, label: 'Grammar Cheat Sheet'),
                            ],
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('QUIZ PROGRESS',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 9, fontWeight: FontWeight.w700,
                                      letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Text('Difficulty',
                                      style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12, color: AppColors.onSurfaceVariant)),
                                  const SizedBox(width: 4),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: AppColors.warningContainer,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text('MODERATE',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: 9,
                                            fontWeight: FontWeight.w700,
                                            color: AppColors.warning)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: const LinearProgressIndicator(
                                  value: 0.6,
                                  backgroundColor: AppColors.surfaceContainerHigh,
                                  valueColor: AlwaysStoppedAnimation(AppColors.warning),
                                  minHeight: 5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ModuleRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ModuleRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 14, color: AppColors.primary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(label,
              style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurface)),
        ),
      ],
    );
  }
}
