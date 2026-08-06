import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../data/content_lab_repository.dart';

class ContentLabScreen extends StatefulWidget {
  const ContentLabScreen({super.key});
  @override
  State<ContentLabScreen> createState() => _ContentLabScreenState();
}

class _ContentLabScreenState extends State<ContentLabScreen> with SingleTickerProviderStateMixin {
  final _repo = ContentLabRepository();
  final _search = TextEditingController();
  late final TabController _tabs;
  List<QuestionItem> _questions = [];
  List<TestExam> _exams = [];
  bool _loading = true;
  String? _error;
  String _level = 'All';

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this)..addListener(() {
      if (!_tabs.indexIsChanging) setState(() { _search.clear(); _level = 'All'; });
    });
    _load();
  }

  @override
  void dispose() { _tabs.dispose(); _search.dispose(); super.dispose(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([_repo.listQuestions(), _repo.listTestExams()]);
      if (!mounted) return;
      setState(() { _questions = results[0] as List<QuestionItem>; _exams = results[1] as List<TestExam>; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Không thể tải Content Lab.'; });
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text, style: GoogleFonts.spaceGrotesk()),
        backgroundColor: error ? AppColors.error : AppColors.success, behavior: SnackBarBehavior.floating));
  }

  Future<void> _delete(String id, String name, bool question) async {
    final yes = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: Text('Xóa ${question ? 'câu hỏi' : 'bài thi'}?'), content: Text(name),
      actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xóa'))]));
    if (yes != true) return;
    try { question ? await _repo.deleteQuestion(id) : await _repo.deleteTestExam(id); await _load(); _message('Đã xóa.'); }
    catch (_) { _message('Xóa thất bại.', error: true); }
  }

  Future<void> _questionForm([QuestionItem? item]) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface, builder: (_) => _QuestionForm(item: item));
    if (payload == null) return;
    try { item == null ? await _repo.createQuestion(payload) : await _repo.updateQuestion(item.id, payload); await _load(); _message('Đã lưu câu hỏi.'); }
    catch (_) { _message('Không thể lưu câu hỏi.', error: true); }
  }

  Future<void> _examForm([TestExam? item]) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(context: context, isScrollControlled: true,
      backgroundColor: AppColors.surface, builder: (_) => _ExamForm(item: item));
    if (payload == null) return;
    try { item == null ? await _repo.createTestExam(payload) : await _repo.updateTestExam(item.id, payload); await _load(); _message('Đã lưu bài thi.'); }
    catch (_) { _message('Không thể lưu bài thi.', error: true); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(backgroundColor: AppColors.background, elevation: 0,
      leading: IconButton(icon: const Icon(Icons.menu_rounded, color: AppColors.onSurface), onPressed: AdminShell.openDrawer),
      title: Text('Content Lab', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, color: AppColors.onSurface)),
      bottom: TabBar(controller: _tabs, labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        labelColor: AppColors.primary, indicatorColor: AppColors.primary,
        tabs: const [Tab(text: 'Questions'), Tab(text: 'Test Exams')]),
    ),
    floatingActionButton: FloatingActionButton.extended(backgroundColor: AppColors.primary, foregroundColor: AppColors.surface,
      onPressed: () => _tabs.index == 0 ? _questionForm() : _examForm(),
      icon: const Icon(Icons.add), label: const Text('Create')),
    body: RefreshIndicator(color: AppColors.primary, onRefresh: _load, child: ListView(
      physics: const AlwaysScrollableScrollPhysics(), padding: const EdgeInsets.fromLTRB(16, 16, 16, 96), children: [
        TextField(controller: _search, onChanged: (_) => setState(() {}),
          decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', border: OutlineInputBorder())),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(initialValue: _level,
          decoration: const InputDecoration(labelText: 'Level', border: OutlineInputBorder()),
          items: const ['All','A1','A2','B1','B2','C1','C2'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
          onChanged: (v) => setState(() => _level = v!)),
        const SizedBox(height: 16),
        if (_loading) const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator(color: AppColors.primary)))
        else if (_error != null) _StateCard(icon: Icons.error_outline, text: _error!, action: _load)
        else _tabs.index == 0 ? _questionList() : _examList(),
      ])),
  );

  Widget _questionList() {
    final q = _search.text.toLowerCase();
    final items = _questions.where((e) => (_level == 'All' || e.difficultyLevel == _level) &&
      (e.prompt.toLowerCase().contains(q) || e.questionType.toLowerCase().contains(q))).toList();
    if (items.isEmpty) return const _StateCard(icon: Icons.quiz_outlined, text: 'Không có câu hỏi.');
    return Column(children: items.map((e) => _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.prompt, maxLines: 3, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16)),
      const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 6, children: [_Chip(e.questionType), _Chip(e.difficultyLevel), _Chip(e.isActive ? 'Active' : 'Inactive')]),
      if (e.tags.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(e.tags.join(' • '), style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted))),
      _Actions(onEdit: () => _questionForm(e), onDelete: () => _delete(e.id, e.prompt, true)),
    ]))).toList());
  }

  Widget _examList() {
    final q = _search.text.toLowerCase();
    final items = _exams.where((e) => (_level == 'All' || e.level == _level) &&
      (e.title.toLowerCase().contains(q) || (e.description ?? '').toLowerCase().contains(q))).toList();
    if (items.isEmpty) return const _StateCard(icon: Icons.assignment_outlined, text: 'Không có bài thi.');
    return Column(children: items.map((e) => _Card(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(e.title, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700, fontSize: 16)),
      if (e.description?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 6), child: Text(e.description!, maxLines: 2, overflow: TextOverflow.ellipsis)),
      const SizedBox(height: 8), Wrap(spacing: 8, runSpacing: 6, children: [_Chip(e.level), _Chip('${e.durationMinutes} min'), _Chip('${e.passingScore}% pass'), _Chip('${e.questionIds.length} questions'), _Chip(e.isPublished ? 'Published' : 'Draft')]),
      _Actions(onEdit: () => _examForm(e), onDelete: () => _delete(e.id, e.title, false)),
    ]))).toList());
  }
}

class _QuestionForm extends StatefulWidget {
  final QuestionItem? item;
  const _QuestionForm({this.item});
  @override State<_QuestionForm> createState() => _QuestionFormState();
}
class _QuestionFormState extends State<_QuestionForm> {
  late final TextEditingController prompt, options, answer, explanation, tags;
  late String type, level; late bool active;
  @override void initState() { super.initState(); final i=widget.item; prompt=TextEditingController(text:i?.prompt); options=TextEditingController(text:i==null?'':jsonEncode(i.options)); answer=TextEditingController(text:i?.answer==null?'':jsonEncode(i!.answer)); explanation=TextEditingController(text:i?.explanation); tags=TextEditingController(text:i?.tags.join(', ')); type=i?.questionType??'mcq'; level=i?.difficultyLevel??'A1'; active=i?.isActive??true; }
  @override Widget build(BuildContext context) => _FormSheet(title: widget.item == null ? 'Create question' : 'Edit question', children: [
    _field(prompt, 'Prompt', lines: 3), _drop('Type', type, const ['mcq','fill_blank','true_false'], (v)=>setState(()=>type=v)),
    _drop('Difficulty', level, const ['A1','A2','B1','B2','C1','C2'], (v)=>setState(()=>level=v)),
    _field(options, 'Options (JSON array)', lines: 2), _field(answer, 'Answer (JSON)', lines: 2),
    _field(explanation, 'Explanation', lines: 2), _field(tags, 'Tags (comma-separated)'),
    SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: active, onChanged: (v)=>setState(()=>active=v)),
    _save(context, () { try { final opts=options.text.trim().isEmpty?<dynamic>[]:jsonDecode(options.text); if (opts is! List) throw const FormatException(); Navigator.pop(context, {'prompt':prompt.text.trim(),'question_type':type,'difficulty_level':level,'options':opts,'answer':answer.text.trim().isEmpty?null:jsonDecode(answer.text),'explanation':explanation.text.trim().isEmpty?null:explanation.text.trim(),'tags':tags.text.split(',').map((e)=>e.trim()).where((e)=>e.isNotEmpty).toList(),'is_active':active}); } catch (_) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Options/answer must be valid JSON.'))); } })
  ]);
}

class _ExamForm extends StatefulWidget { final TestExam? item; const _ExamForm({this.item}); @override State<_ExamForm> createState()=>_ExamFormState(); }
class _ExamFormState extends State<_ExamForm> {
  late final TextEditingController title, description, duration, score; late String level; late bool published;
  @override void initState(){super.initState();final i=widget.item;title=TextEditingController(text:i?.title);description=TextEditingController(text:i?.description);duration=TextEditingController(text:'${i?.durationMinutes??20}');score=TextEditingController(text:'${i?.passingScore??70}');level=i?.level??'A1';published=i?.isPublished??false;}
  @override Widget build(BuildContext context)=>_FormSheet(title:widget.item==null?'Create test exam':'Edit test exam',children:[
    _field(title,'Title'),_field(description,'Description',lines:3),_drop('Level',level,const ['A1','A2','B1','B2','C1','C2'],(v)=>setState(()=>level=v)),
    _field(duration,'Duration (minutes)',number:true),_field(score,'Passing score (%)',number:true),
    if(widget.item!=null) Padding(padding:const EdgeInsets.symmetric(vertical:8),child:Text('${widget.item!.questionIds.length} questions (read-only)',style:GoogleFonts.spaceGrotesk(color:AppColors.onSurfaceMuted))),
    SwitchListTile(contentPadding:EdgeInsets.zero,title:const Text('Published'),value:published,onChanged:(v)=>setState(()=>published=v)),
    _save(context,(){final d=int.tryParse(duration.text),s=int.tryParse(score.text);if(title.text.trim().isEmpty||d==null||d<=0||s==null||s<0||s>100){ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Enter a title, positive duration, and score from 0–100.')));return;}Navigator.pop(context,{'title':title.text.trim(),'description':description.text.trim().isEmpty?null:description.text.trim(),'level':level,'duration_minutes':d,'passing_score':s,'is_published':published});})
  ]);
}

class _FormSheet extends StatelessWidget { final String title; final List<Widget> children; const _FormSheet({required this.title,required this.children}); @override Widget build(BuildContext context)=>SafeArea(child:Padding(padding:EdgeInsets.fromLTRB(20,20,20,MediaQuery.viewInsetsOf(context).bottom+20),child:SingleChildScrollView(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[Text(title,style:GoogleFonts.spaceGrotesk(fontSize:22,fontWeight:FontWeight.w700)),const SizedBox(height:16),...children])))); }
Widget _field(TextEditingController c,String label,{int lines=1,bool number=false})=>Padding(padding:const EdgeInsets.only(bottom:12),child:TextField(controller:c,maxLines:lines,keyboardType:number?TextInputType.number:null,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
Widget _drop(String label,String value,List<String> options,ValueChanged<String> change)=>Padding(padding:const EdgeInsets.only(bottom:12),child:DropdownButtonFormField<String>(initialValue:value,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder()),items:options.map((e)=>DropdownMenuItem(value:e,child:Text(e))).toList(),onChanged:(v)=>change(v!)));
Widget _save(BuildContext context,VoidCallback onPressed)=>SizedBox(height:48,child:FilledButton(onPressed:onPressed,child:const Text('Save')));
class _Card extends StatelessWidget { final Widget child; const _Card({required this.child}); @override Widget build(BuildContext context)=>Container(margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(16),decoration:BoxDecoration(color:AppColors.surface,borderRadius:BorderRadius.circular(14),border:Border.all(color:AppColors.outline)),child:child); }
class _Chip extends StatelessWidget { final String text; const _Chip(this.text); @override Widget build(BuildContext context)=>Container(padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),decoration:BoxDecoration(color:AppColors.surfaceContainerLow,borderRadius:BorderRadius.circular(20)),child:Text(text,style:GoogleFonts.spaceGrotesk(fontSize:12,color:AppColors.onSurfaceMuted))); }
class _Actions extends StatelessWidget { final VoidCallback onEdit,onDelete; const _Actions({required this.onEdit,required this.onDelete}); @override Widget build(BuildContext context)=>Row(mainAxisAlignment:MainAxisAlignment.end,children:[IconButton(constraints:const BoxConstraints(minWidth:44,minHeight:44),tooltip:'Edit',onPressed:onEdit,icon:const Icon(Icons.edit_outlined)),IconButton(constraints:const BoxConstraints(minWidth:44,minHeight:44),tooltip:'Delete',onPressed:onDelete,icon:const Icon(Icons.delete_outline,color:AppColors.error))]); }
class _StateCard extends StatelessWidget { final IconData icon; final String text; final Future<void> Function()? action; const _StateCard({required this.icon,required this.text,this.action}); @override Widget build(BuildContext context)=>Padding(padding:const EdgeInsets.all(40),child:Column(children:[Icon(icon,size:48,color:AppColors.onSurfaceMuted),const SizedBox(height:12),Text(text,textAlign:TextAlign.center,style:GoogleFonts.spaceGrotesk(color:AppColors.onSurfaceMuted)),if(action!=null)TextButton(onPressed:action,child:const Text('Retry'))])); }
