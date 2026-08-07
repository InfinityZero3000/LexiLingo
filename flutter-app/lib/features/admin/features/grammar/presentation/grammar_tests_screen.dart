import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';

class GrammarTestsScreen extends StatefulWidget {
  const GrammarTestsScreen({super.key});
  @override
  State<GrammarTestsScreen> createState() => _GrammarTestsScreenState();
}

class _GrammarTestsScreenState extends State<GrammarTestsScreen> {
  List<Map<String, dynamic>> _rules = [];
  bool _loading = true;
  String? _error;
  String _search = '';
  String? _level;
  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  List<Map<String, dynamic>> get _filtered => _rules.where((rule) {
        final query = _search.toLowerCase();
        final matchesText = (rule['title'] ?? '').toString().toLowerCase().contains(query) ||
            (rule['topic'] ?? '').toString().toLowerCase().contains(query);
        return matchesText && (_level == null || '${rule['level'] ?? rule['cefr_level']}' == _level);
      }).toList();

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final response = await ApiClient.instance.get(ApiEndpoints.adminGrammar, params: {'limit': 100, 'offset': 0});
      final data = response['data'];
      final list = data is Map ? data['items'] ?? data['grammar'] ?? [] : data ?? [];
      if (mounted) setState(() => _rules = List<Map<String, dynamic>>.from(list));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load grammar rules.\n$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showForm([Map<String, dynamic>? rule]) => showModalBottomSheet<void>(
        context: context, isScrollControlled: true, backgroundColor: Colors.transparent,
        builder: (_) => _GrammarForm(rule: rule, onSaved: _load),
      );

  Future<void> _delete(Map<String, dynamic> rule) async {
    final confirmed = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Delete grammar rule?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      content: Text('${rule['title']}', style: GoogleFonts.spaceGrotesk()),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete'))],
    ));
    if (confirmed != true) return;
    try { await ApiClient.instance.delete('${ApiEndpoints.adminGrammar}/${rule['id']}'); await _load(); }
    catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $error'))); }
  }

  @override
  Widget build(BuildContext context) {
    final rules = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: AdminShell.openDrawer),
        title: Text('Grammar', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_outlined))],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(children: [
            Expanded(child: TextField(onChanged: (value) => setState(() => _search = value), style: GoogleFonts.spaceGrotesk(), decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search rules…'))),
            const SizedBox(width: 8),
            SizedBox(width: 92, child: DropdownButtonFormField<String>(initialValue: _level, decoration: const InputDecoration(hintText: 'Level'), items: [const DropdownMenuItem<String>(value: null, child: Text('All')), ..._levels.map((v) => DropdownMenuItem(value: v, child: Text(v)))], onChanged: (v) => setState(() => _level = v))),
          ]),
        ),
        Expanded(child: _loading
            ? ListView(padding: const EdgeInsets.all(16), children: const [SectionCardSkeleton(contentHeight: 100), SizedBox(height: 12), SectionCardSkeleton(contentHeight: 100)])
            : _error != null
                ? _GrammarMessage(message: _error!, action: _load)
                : RefreshIndicator(
                    onRefresh: _load,
                    child: rules.isEmpty
                        ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [const SizedBox(height: 180), _GrammarMessage(message: _search.isEmpty && _level == null ? 'No grammar rules yet' : 'No matching rules')])
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 0, 16, 96), itemCount: rules.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 10),
                            itemBuilder: (_, index) => StaggeredEntrance(index: index, child: _ruleCard(rules[index])),
                          ),
                  )),
      ]),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(), backgroundColor: AppColors.primaryBright, foregroundColor: AppColors.surface,
        icon: const Icon(Icons.add), label: Text('New rule', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _ruleCard(Map<String, dynamic> rule) => Material(
    color: AppColors.surface, borderRadius: BorderRadius.circular(14),
    child: InkWell(
      borderRadius: BorderRadius.circular(14), onTap: () => _showForm(rule),
      child: Padding(padding: const EdgeInsets.all(16), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 44, height: 44, alignment: Alignment.center, decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(10)), child: Text('${rule['level'] ?? rule['cefr_level'] ?? '?'}', style: GoogleFonts.spaceGrotesk(color: AppColors.primary, fontWeight: FontWeight.w700))),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${rule['title'] ?? 'Untitled'}', style: GoogleFonts.spaceGrotesk(fontSize: 15, fontWeight: FontWeight.w700)),
          if ((rule['topic'] ?? '').toString().isNotEmpty) Text('${rule['topic']}', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.primary)),
          if ((rule['summary'] ?? '').toString().isNotEmpty) Padding(padding: const EdgeInsets.only(top: 4), child: Text('${rule['summary']}', maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted))),
        ])),
        SizedBox(width: 44, height: 44, child: IconButton(tooltip: 'Delete', onPressed: () => _delete(rule), icon: const Icon(Icons.delete_outline, color: AppColors.error))),
      ])),
    ),
  );
}

class _GrammarForm extends StatefulWidget {
  final Map<String, dynamic>? rule;
  final Future<void> Function() onSaved;
  const _GrammarForm({this.rule, required this.onSaved});
  @override
  State<_GrammarForm> createState() => _GrammarFormState();
}

class _GrammarFormState extends State<_GrammarForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title, _topic, _summary, _content, _tags;
  late String _level;
  bool _saving = false;
  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    final rule = widget.rule ?? {};
    _title = TextEditingController(text: '${rule['title'] ?? ''}');
    _topic = TextEditingController(text: '${rule['topic'] ?? ''}');
    _summary = TextEditingController(text: '${rule['summary'] ?? ''}');
    _content = TextEditingController(text: '${rule['content'] ?? ''}');
    _tags = TextEditingController(text: (rule['tags'] is List ? (rule['tags'] as List).join(', ') : rule['tags'] ?? '').toString());
    _level = '${rule['level'] ?? rule['cefr_level'] ?? 'A1'}';
  }

  @override
  void dispose() { _title.dispose(); _topic.dispose(); _summary.dispose(); _content.dispose(); _tags.dispose(); super.dispose(); }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = {
      'title': _title.text.trim(), 'level': _level, 'topic': _topic.text.trim(),
      'summary': _summary.text.trim(), 'content': _content.text.trim(),
      'tags': _tags.text.split(',').map((v) => v.trim()).where((v) => v.isNotEmpty).toList(),
    };
    try {
      final id = widget.rule?['id'];
      if (id == null) { await ApiClient.instance.post(ApiEndpoints.adminGrammar, data: payload); }
      else { await ApiClient.instance.put('${ApiEndpoints.adminGrammar}/$id', data: payload); }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $error'))); }
    finally { if (mounted) setState(() => _saving = false); }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String label) => InputDecoration(labelText: label);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface, borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(top: false, child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Form(key: _formKey, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.rule == null ? 'New grammar rule' : 'Edit grammar rule', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          TextFormField(controller: _title, decoration: decoration('Title *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(initialValue: _level, decoration: decoration('Level'), items: _levels.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _level = v!)),
          const SizedBox(height: 12),
          TextFormField(controller: _topic, decoration: decoration('Topic')),
          const SizedBox(height: 12),
          TextFormField(controller: _summary, decoration: decoration('Summary')),
          const SizedBox(height: 12),
          TextFormField(controller: _content, decoration: decoration('Content *'), minLines: 3, maxLines: 6, validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
          const SizedBox(height: 12),
          TextFormField(controller: _tags, decoration: decoration('Tags (comma separated)')),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.rule == null ? 'Create' : 'Update'))),
        ])))),
      ),
    );
  }
}

class _GrammarMessage extends StatelessWidget {
  final String message;
  final Future<void> Function()? action;
  const _GrammarMessage({required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.rule_folder_outlined, size: 42, color: AppColors.onSurfaceMuted), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)), if (action != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: action, child: const Text('Try again'))]])));
}
