import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

class GrammarTestsScreen extends StatefulWidget {
  const GrammarTestsScreen({super.key});

  @override
  State<GrammarTestsScreen> createState() => _GrammarTestsScreenState();
}

class _GrammarTestsScreenState extends State<GrammarTestsScreen> {
  List<Map<String, dynamic>> _modules = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final resp = await ApiClient.instance.get('/admin/test-exams', params: {'page': 1, 'page_size': 10});
      final data = resp['data'];
      final list = data is Map ? data['exams'] ?? data['items'] ?? [] : data ?? [];
      if (mounted) setState(() { _modules = List<Map<String, dynamic>>.from(list); _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('Grammar & Tests',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Deploy linguistic rules, monitor assessment accuracy, and manage adaptive test modules.',
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            // Rule Engine Status
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.primaryBright,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Rule Engine Status',
                            style: GoogleFonts.spaceGrotesk(
                                fontSize: 14, fontWeight: FontWeight.w700, color: Colors.white)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.check_circle, color: Colors.greenAccent, size: 14),
                            const SizedBox(width: 4),
                            Text('V3.4 DEPLOYED ACTIVE',
                                style: GoogleFonts.spaceGrotesk(
                                    fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white60)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.white54),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    child: Text('PUSH NEW UPDATE',
                        style: GoogleFonts.spaceGrotesk(fontSize: 10, fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Stats
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: const [
                _GrammarStat(label: 'AVG. ACCURACY', value: '94.2%', icon: Icons.gps_fixed_outlined),
                _GrammarStat(label: 'ACTIVE TESTS', value: '1,204', icon: Icons.quiz_outlined),
                _GrammarStat(label: 'ERR MARGIN', value: '1.4%', icon: Icons.warning_amber_outlined),
                _GrammarStat(label: 'AI ADAPTIVITY', value: 'High', icon: Icons.psychology_outlined),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Test Modules',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    decoration: const InputDecoration(
                      hintText: 'Search modules...',
                      prefixIcon: Icon(Icons.search, size: 18, color: AppColors.onSurfaceMuted),
                      isDense: true,
                    ),
                    style: GoogleFonts.spaceGrotesk(fontSize: 13),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppColors.primary))
            else if (_modules.isEmpty)
              ..._defaultModules.map(_buildModuleCard)
            else
              ..._modules.map(_buildModuleCard),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: AppColors.primaryBright,
        onPressed: () {},
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }

  static final _defaultModules = [
    {'title': 'Verb Conjugation V4', 'description': 'Deep dive into irregular past participles and subjunctive moods.', 'level': 'ADVANCED'},
    {'title': 'Sentence Architect', 'description': 'Mastering complex clause structures and rhetorical devices.', 'level': 'INTERMEDIATE'},
    {'title': 'Foundation Syntax', 'description': 'Core subject-verb-object relationships for 12 key languages.', 'level': 'BEGINNER'},
  ];

  Widget _buildModuleCard(Map<String, dynamic> m) {
    final level = m['level'] ?? m['cefr_level'] ?? 'INTERMEDIATE';
    final levelColor = level == 'ADVANCED'
        ? AppColors.error
        : level == 'BEGINNER'
            ? AppColors.success
            : AppColors.warning;
    final levelBg = level == 'ADVANCED'
        ? AppColors.errorContainer
        : level == 'BEGINNER'
            ? AppColors.successContainer
            : AppColors.warningContainer;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            height: 80,
            decoration: BoxDecoration(
              color: AppColors.navy,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Stack(
              children: [
                Center(
                  child: Icon(Icons.menu_book_outlined,
                      color: Colors.white24, size: 40),
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: levelBg,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(level,
                        style: GoogleFonts.spaceGrotesk(
                            fontSize: 9, fontWeight: FontWeight.w700, color: levelColor)),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m['title'] ?? '',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
                const SizedBox(height: 4),
                Text(m['description'] ?? '',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 12, color: AppColors.onSurfaceMuted),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 10),
                Row(
                  children: [
                    const Icon(Icons.more_vert, size: 16, color: AppColors.onSurfaceMuted),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrammarStat extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _GrammarStat({required this.label, required this.value, required this.icon});

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
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppColors.primaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: AppColors.primary, size: 15),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 9, fontWeight: FontWeight.w700,
                  letterSpacing: 0.08, color: AppColors.onSurfaceMuted)),
          Text(value,
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 22, fontWeight: FontWeight.w700,
                  color: AppColors.onSurface, letterSpacing: -0.02)),
        ],
      ),
    );
  }
}
