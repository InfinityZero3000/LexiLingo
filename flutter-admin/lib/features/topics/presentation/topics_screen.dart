import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

class TopicsScreen extends StatefulWidget {
  const TopicsScreen({super.key});

  @override
  State<TopicsScreen> createState() => _TopicsScreenState();
}

class _TopicsScreenState extends State<TopicsScreen> {
  List<Map<String, dynamic>> _topics = [];
  List<Map<String, dynamic>> _filtered = [];
  bool _loading = true;
  String _search = '';
  String? _levelFilter;

  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await ApiClient.instance.get('/admin/grammar', params: {'page': 1, 'page_size': 50});
      final data = resp['data'];
      final list = data is Map ? data['items'] ?? data['grammar'] ?? [] : data ?? [];
      if (mounted) {
        setState(() {
          _topics = List<Map<String, dynamic>>.from(list);
          _applyFilter();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilter() {
    _filtered = _topics.where((t) {
      final title = (t['title'] ?? '').toString().toLowerCase();
      final level = (t['cefr_level'] ?? t['level'] ?? '').toString();
      final matchSearch = _search.isEmpty || title.contains(_search.toLowerCase());
      final matchLevel = _levelFilter == null || level == _levelFilter;
      return matchSearch && matchLevel;
    }).toList();
  }

  Color _levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'A1': return const Color(0xFF2AA7A1);
      case 'A2': return const Color(0xFF2196F3);
      case 'B1': return const Color(0xFF7B61FF);
      case 'B2': return const Color(0xFFFF9F2D);
      case 'C1': return const Color(0xFFFF4D00);
      case 'C2': return const Color(0xFFBA1A1A);
      default:   return AppColors.onSurfaceMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('Topics',
            style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_outlined, color: AppColors.onSurface),
            onPressed: _load,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (v) => setState(() { _search = v; _applyFilter(); }),
                    style: GoogleFonts.spaceGrotesk(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search topics…',
                      hintStyle: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted),
                      prefixIcon: const Icon(Icons.search, size: 18, color: AppColors.onSurfaceMuted),
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _levelFilter,
                    hint: Text('Level', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurface),
                    items: [
                      DropdownMenuItem<String?>(value: null, child: Text('All', style: GoogleFonts.spaceGrotesk(fontSize: 12))),
                      ..._levels.map((l) => DropdownMenuItem<String?>(
                          value: l, child: Text(l, style: GoogleFonts.spaceGrotesk(fontSize: 12)))),
                    ],
                    onChanged: (v) => setState(() { _levelFilter = v; _applyFilter(); }),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Row(
              children: [
                Text('${_filtered.length} topics',
                    style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
              ],
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _filtered.isEmpty
                    ? Center(
                        child: Text('No topics found',
                            style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)))
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: _filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (ctx, i) {
                          final t = _filtered[i];
                          final level = (t['cefr_level'] ?? t['level'] ?? '').toString().toUpperCase();
                          final title = t['title']?.toString() ?? 'Untitled';
                          final examples = (t['examples'] as List?)?.length ?? 0;
                          return Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: AppColors.surface,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: AppColors.outline, width: 0.5),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: _levelColor(level).withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Center(
                                    child: Text(level.isNotEmpty ? level : '?',
                                        style: GoogleFonts.spaceGrotesk(
                                            fontSize: level.length > 2 ? 8 : 11,
                                            fontWeight: FontWeight.w700,
                                            color: _levelColor(level))),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(title,
                                          style: GoogleFonts.spaceGrotesk(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: AppColors.onSurface)),
                                      if (examples > 0)
                                        Text('$examples examples',
                                            style: GoogleFonts.spaceGrotesk(
                                                fontSize: 11, color: AppColors.onSurfaceMuted)),
                                    ],
                                  ),
                                ),
                                const Icon(Icons.chevron_right,
                                    size: 16, color: AppColors.onSurfaceMuted),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showAddTopicSheet(context),
        backgroundColor: AppColors.primaryBright,
        icon: const Icon(Icons.add, color: Colors.white),
        label: Text('New Topic',
            style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700, color: Colors.white, fontSize: 13)),
      ),
    );
  }

  void _showAddTopicSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AddTopicSheet(onCreated: _load),
    );
  }
}

class _AddTopicSheet extends StatefulWidget {
  final VoidCallback onCreated;
  const _AddTopicSheet({required this.onCreated});

  @override
  State<_AddTopicSheet> createState() => _AddTopicSheetState();
}

class _AddTopicSheetState extends State<_AddTopicSheet> {
  final _titleCtrl = TextEditingController();
  final _contentCtrl = TextEditingController();
  String _level = 'B1';
  bool _saving = false;

  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1'];

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  Future<void> _save(BuildContext context) async {
    if (_titleCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await ApiClient.instance.post('/admin/grammar', data: {
        'title': _titleCtrl.text.trim(),
        'content': _contentCtrl.text.trim(),
        'cefr_level': _level,
        'examples': [],
      });
      widget.onCreated();
      if (context.mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _saving = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to create topic: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: AppColors.outline,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            Text('New Topic',
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 18, fontWeight: FontWeight.w700, color: AppColors.onSurface)),
            const SizedBox(height: 16),
            TextField(
              controller: _titleCtrl,
              style: GoogleFonts.spaceGrotesk(fontSize: 14),
              decoration: InputDecoration(
                labelText: 'Title',
                labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _contentCtrl,
              maxLines: 3,
              style: GoogleFonts.spaceGrotesk(fontSize: 13),
              decoration: InputDecoration(
                labelText: 'Rule / Explanation',
                labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12),
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _level,
              decoration: InputDecoration(
                  labelText: 'CEFR Level',
                  labelStyle: GoogleFonts.spaceGrotesk(fontSize: 12)),
              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurface),
              items: _levels
                  .map((l) => DropdownMenuItem(value: l, child: Text(l)))
                  .toList(),
              onChanged: (v) => setState(() => _level = v ?? _level),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : () => _save(context),
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primaryBright,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12))),
                child: _saving
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text('Create Topic',
                        style: GoogleFonts.spaceGrotesk(
                            fontWeight: FontWeight.w700, color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
