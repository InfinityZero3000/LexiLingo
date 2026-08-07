import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/staggered_entrance.dart';

class VocabularyScreen extends StatefulWidget {
  const VocabularyScreen({super.key});

  @override
  State<VocabularyScreen> createState() => _VocabularyScreenState();
}

class _VocabularyScreenState extends State<VocabularyScreen> {
  List<Map<String, dynamic>> _words = [];
  bool _loading = true;
  String? _error;
  String _search = '';

  List<Map<String, dynamic>> get _filtered => _words.where((word) {
        final query = _search.toLowerCase();
        return (word['word'] ?? '').toString().toLowerCase().contains(query) ||
            (word['definition'] ?? '').toString().toLowerCase().contains(query);
      }).toList();

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
      final response = await ApiClient.instance.get(
        ApiEndpoints.adminVocabulary,
        params: {'limit': 100, 'offset': 0},
      );
      final data = response['data'];
      final list = data is Map ? data['items'] ?? data['vocabulary'] ?? [] : data ?? [];
      if (mounted) setState(() => _words = List<Map<String, dynamic>>.from(list));
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load vocabulary.\n$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _delete(Map<String, dynamic> word) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${word['word']}”?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        content: Text('This action cannot be undone.', style: GoogleFonts.spaceGrotesk()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ApiClient.instance.delete('${ApiEndpoints.adminVocabulary}/${word['id']}');
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Delete failed: $error')));
    }
  }

  void _showForm([Map<String, dynamic>? word]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VocabularyForm(word: word, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    final words = _filtered;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: AdminShell.openDrawer),
        title: Text('Vocabulary Library', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_outlined))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: TextField(
              onChanged: (value) => setState(() => _search = value),
              style: GoogleFonts.spaceGrotesk(),
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search words or definitions…'),
            ),
          ),
          Expanded(
            child: _loading
                ? ListView(padding: const EdgeInsets.all(16), children: const [SectionCardSkeleton(contentHeight: 110), SizedBox(height: 12), SectionCardSkeleton(contentHeight: 110)])
                : _error != null
                    ? _MessageState(icon: Icons.cloud_off_outlined, message: _error!, action: _load)
                    : RefreshIndicator(
                        onRefresh: _load,
                        child: words.isEmpty
                            ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: [SizedBox(height: 180), _MessageState(icon: Icons.menu_book_outlined, message: _search.isEmpty ? 'No vocabulary yet' : 'No matching words')])
                            : ListView.separated(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                                itemCount: words.length,
                                separatorBuilder: (_, __) => const SizedBox(height: 10),
                                itemBuilder: (_, index) => StaggeredEntrance(index: index, child: _wordCard(words[index])),
                              ),
                      ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showForm(),
        backgroundColor: AppColors.primaryBright,
        foregroundColor: AppColors.surface,
        icon: const Icon(Icons.add),
        label: Text('New word', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _wordCard(Map<String, dynamic> word) {
    final translation = word['translation'];
    final translated = translation is Map ? translation['vi'] : translation;
    return Material(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _showForm(word),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text('${word['word'] ?? ''}', style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700))),
                    const SizedBox(width: 8),
                    _LevelChip('${word['difficulty_level'] ?? 'A1'}'),
                  ]),
                  if ((word['pronunciation'] ?? '').toString().isNotEmpty)
                    Text('${word['pronunciation']}', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
                  const SizedBox(height: 6),
                  Text('${word['definition'] ?? 'No definition'}', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceVariant)),
                  if ((translated ?? '').toString().isNotEmpty)
                    Text('$translated', style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
                  const SizedBox(height: 6),
                  Text('${word['part_of_speech'] ?? '—'}', style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.primary, fontWeight: FontWeight.w600)),
                ]),
              ),
              SizedBox(width: 44, height: 44, child: IconButton(tooltip: 'Delete', onPressed: () => _delete(word), icon: const Icon(Icons.delete_outline, color: AppColors.error))),
            ],
          ),
        ),
      ),
    );
  }
}

class _VocabularyForm extends StatefulWidget {
  final Map<String, dynamic>? word;
  final Future<void> Function() onSaved;
  const _VocabularyForm({this.word, required this.onSaved});

  @override
  State<_VocabularyForm> createState() => _VocabularyFormState();
}

class _VocabularyFormState extends State<_VocabularyForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _word;
  late final TextEditingController _definition;
  late final TextEditingController _translation;
  late final TextEditingController _pronunciation;
  late String _partOfSpeech;
  late String _level;
  bool _saving = false;

  static const _parts = ['noun', 'verb', 'adjective', 'adverb', 'pronoun', 'preposition', 'conjunction', 'interjection'];
  static const _levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

  @override
  void initState() {
    super.initState();
    final item = widget.word ?? {};
    final translation = item['translation'];
    _word = TextEditingController(text: '${item['word'] ?? ''}');
    _definition = TextEditingController(text: '${item['definition'] ?? ''}');
    _translation = TextEditingController(text: '${translation is Map ? translation['vi'] ?? '' : translation ?? ''}');
    _pronunciation = TextEditingController(text: '${item['pronunciation'] ?? ''}');
    _partOfSpeech = '${item['part_of_speech'] ?? 'noun'}';
    _level = '${item['difficulty_level'] ?? 'A1'}';
  }

  @override
  void dispose() {
    _word.dispose(); _definition.dispose(); _translation.dispose(); _pronunciation.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = {
      'word': _word.text.trim(), 'definition': _definition.text.trim(),
      'translation': _translation.text.trim(), 'part_of_speech': _partOfSpeech,
      'pronunciation': _pronunciation.text.trim(), 'difficulty_level': _level,
    };
    final query = Uri(queryParameters: values).query;
    final id = widget.word?['id'];
    try {
      if (id == null) {
        await ApiClient.instance.post('${ApiEndpoints.adminVocabulary}?$query');
      } else {
        await ApiClient.instance.put('${ApiEndpoints.adminVocabulary}/$id?$query');
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    InputDecoration decoration(String label) => InputDecoration(labelText: label);
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Material(
        color: AppColors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Form(
              key: _formKey,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.word == null ? 'New word' : 'Edit word', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
                const SizedBox(height: 16),
                TextFormField(controller: _word, decoration: decoration('Word *'), validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _definition, decoration: decoration('Definition *'), maxLines: 2, validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null),
                const SizedBox(height: 12),
                TextFormField(controller: _translation, decoration: decoration('Vietnamese translation')),
                const SizedBox(height: 12),
                TextFormField(controller: _pronunciation, decoration: decoration('Pronunciation')),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _partOfSpeech, decoration: decoration('Part of speech'), items: _parts.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _partOfSpeech = v!))),
                  const SizedBox(width: 12),
                  Expanded(child: DropdownButtonFormField<String>(initialValue: _level, decoration: decoration('Level'), items: _levels.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => _level = v!))),
                ]),
                const SizedBox(height: 20),
                SizedBox(width: double.infinity, height: 48, child: FilledButton(onPressed: _saving ? null : _save, child: _saving ? const SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Text(widget.word == null ? 'Create' : 'Update'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelChip extends StatelessWidget {
  final String level;
  const _LevelChip(this.level);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(6)),
        child: Text(level, style: GoogleFonts.spaceGrotesk(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
      );
}

class _MessageState extends StatelessWidget {
  final IconData icon;
  final String message;
  final Future<void> Function()? action;
  const _MessageState({required this.icon, required this.message, this.action});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 40, color: AppColors.onSurfaceMuted), const SizedBox(height: 12), Text(message, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)), if (action != null) ...[const SizedBox(height: 12), OutlinedButton(onPressed: action, child: const Text('Try again'))]])));
}
