import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';

import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../data/lesson_exercises_repository.dart';

const _uiTypeLabels = <String, String>{
  'multiple_choice': 'Multiple Choice',
  'true_or_false': 'True or False',
  'fill_in_the_blank': 'Fill in the Blank',
  'arrange_the_sentence': 'Arrange the Sentence',
  'translation_choice': 'Translation Choice',
  'dialogue_completion': 'Dialogue Completion',
  'collocation_choice': 'Collocation Choice',
  'dictation': 'Dictation',
  'grammar_correction': 'Grammar Correction',
  'image_based_choice': 'Image Based Choice',
  'listen_and_choose': 'Listen and Choose',
  'match_word_to_meaning': 'Match Word to Meaning',
  'vocabulary_flashcard': 'Vocabulary Flashcard',
  'pronunciation_practice': 'Pronunciation Practice',
  'reading_comprehension': 'Reading Comprehension',
  'short_writing_answer': 'Short Writing Answer',
  'speaking_repeat': 'Speaking Repeat',
  'categorization': 'Categorization',
  'cognitive_fluidity': 'Cognitive Fluidity',
};

const _uiTypeToType = <String, String>{
  'multiple_choice': 'multiple_choice',
  'true_or_false': 'true_false',
  'fill_in_the_blank': 'fill_blank',
  'arrange_the_sentence': 'reorder',
  'translation_choice': 'translate',
  'dialogue_completion': 'fill_blank',
  'collocation_choice': 'multiple_choice',
  'dictation': 'fill_blank',
  'grammar_correction': 'fill_blank',
  'image_based_choice': 'multiple_choice',
  'listen_and_choose': 'multiple_choice',
  'match_word_to_meaning': 'matching',
  'vocabulary_flashcard': 'multiple_choice',
  'pronunciation_practice': 'translate',
  'reading_comprehension': 'multiple_choice',
  'short_writing_answer': 'fill_blank',
  'speaking_repeat': 'translate',
  'categorization': 'matching',
  'cognitive_fluidity': 'matching',
};

const _choiceTypes = <String>{
  'multiple_choice',
  'true_or_false',
  'translation_choice',
  'dialogue_completion',
  'collocation_choice',
  'image_based_choice',
  'listen_and_choose',
  'vocabulary_flashcard',
  'reading_comprehension',
};

class LessonExercisesScreen extends StatefulWidget {
  final String lessonId;
  final String lessonTitle;

  const LessonExercisesScreen({
    super.key,
    required this.lessonId,
    required this.lessonTitle,
  });

  @override
  State<LessonExercisesScreen> createState() =>
      _LessonExercisesScreenState();
}

class _LessonExercisesScreenState extends State<LessonExercisesScreen> {
  final _repository = LessonExercisesRepository();
  List<Exercise> _exercises = [];
  bool _loading = true;
  bool _saving = false;
  bool _dirty = false;
  int _revision = 0;
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
      final exercises = await _repository.getLessonContent(widget.lessonId);
      if (!mounted) return;
      setState(() {
        _exercises = exercises;
        _loading = false;
        _dirty = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load lesson exercises.';
      });
    }
  }

  Future<void> _save() async {
    final revision = _revision;
    final exercises = List<Exercise>.of(_exercises);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _repository.saveLessonContent(widget.lessonId, exercises);
      if (!mounted) return;
      setState(() {
        _saving = false;
        if (_revision == revision) _dirty = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Exercises saved successfully.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save lesson exercises.';
      });
    }
  }

  Future<void> _editExercise([int? index]) async {
    final exercise = index == null ? null : _exercises[index];
    final updated = await Navigator.of(context).push<Exercise>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => _ExerciseEditor(exercise: exercise),
      ),
    );
    if (updated == null || !mounted) return;
    setState(() {
      if (index == null) {
        _exercises.add(updated);
      } else {
        _exercises[index] = updated;
      }
      _revision++;
      _dirty = true;
    });
  }

  Future<void> _deleteExercise(int index) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete exercise?', style: GoogleFonts.spaceGrotesk()),
        content: Text(
          'This removes exercise ${index + 1} from the lesson.',
          style: GoogleFonts.spaceGrotesk(),
        ),
        actions: [
          TextButton(
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
    if (confirmed != true || !mounted) return;
    setState(() {
      _exercises.removeAt(index);
      _revision++;
      _dirty = true;
    });
  }

  void _move(int index, int offset) {
    final target = index + offset;
    if (target < 0 || target >= _exercises.length) return;
    setState(() {
      final exercise = _exercises.removeAt(index);
      _exercises.insert(target, exercise);
      _revision++;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        leading: AppBackButton(
          icon: Icons.arrow_back,
          color: AppColors.onSurface,
          onPressed: () => context.pop(),
        ),
        title: Text(
          widget.lessonTitle,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.spaceGrotesk(
            color: AppColors.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton.icon(
              onPressed: _dirty && !_saving ? _save : null,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Saving' : 'Save'),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : () => _editExercise(),
        backgroundColor: AppColors.primaryBright,
        foregroundColor: AppColors.surface,
        icon: const Icon(Icons.add),
        label: Text(
          'Add exercise',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 100),
          children: [
            Text(
              'LESSON CONTENT',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.primary,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '${_exercises.length} exercises',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface,
                fontSize: 26,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 20),
            if (_error != null) ...[
              _ErrorBanner(message: _error!, onRetry: _loading ? null : _load),
              const SizedBox(height: 12),
            ],
            if (_loading)
              const Column(
                children: [
                  AdminSkeleton(height: 112),
                  SizedBox(height: 12),
                  AdminSkeleton(height: 112),
                ],
              )
            else if (_exercises.isEmpty)
              _EmptyState(onAdd: () => _editExercise())
            else
              ...List.generate(
                _exercises.length,
                (index) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _ExerciseCard(
                    exercise: _exercises[index],
                    index: index,
                    total: _exercises.length,
                    onMoveUp: () => _move(index, -1),
                    onMoveDown: () => _move(index, 1),
                    onEdit: () => _editExercise(index),
                    onDelete: () => _deleteExercise(index),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseCard extends StatelessWidget {
  final Exercise exercise;
  final int index;
  final int total;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _ExerciseCard({
    required this.exercise,
    required this.index,
    required this.total,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: AppColors.surfaceDim,
                foregroundColor: AppColors.onSurface,
                child: Text('${index + 1}'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: AppColors.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    _uiTypeLabels[exercise.uiType] ?? exercise.uiType,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.spaceGrotesk(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${exercise.points} pts',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.onSurfaceMuted,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            exercise.question.trim().isEmpty
                ? 'No question text'
                : exercise.question,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(
              color: AppColors.onSurfaceVariant,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionButton(
                tooltip: 'Move up',
                icon: Icons.keyboard_arrow_up,
                onPressed: index == 0 ? null : onMoveUp,
              ),
              _ActionButton(
                tooltip: 'Move down',
                icon: Icons.keyboard_arrow_down,
                onPressed: index == total - 1 ? null : onMoveDown,
              ),
              _ActionButton(
                tooltip: 'Edit',
                icon: Icons.edit_outlined,
                onPressed: onEdit,
              ),
              _ActionButton(
                tooltip: 'Delete',
                icon: Icons.delete_outline,
                color: AppColors.error,
                onPressed: onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? color;

  const _ActionButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.color,
  });

  @override
  Widget build(BuildContext context) => IconButton(
        constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
        tooltip: tooltip,
        onPressed: onPressed,
        color: color ?? AppColors.onSurfaceMuted,
        icon: Icon(icon),
      );
}

class _ExerciseEditor extends StatefulWidget {
  final Exercise? exercise;

  const _ExerciseEditor({this.exercise});

  @override
  State<_ExerciseEditor> createState() => _ExerciseEditorState();
}

class _ExerciseEditorState extends State<_ExerciseEditor> {
  final _formKey = GlobalKey<FormState>();
  late String _uiType;
  late final TextEditingController _question;
  late final TextEditingController _correctAnswer;
  late final TextEditingController _explanation;
  late final TextEditingController _hint;
  late final TextEditingController _audioUrl;
  late final TextEditingController _imageUrl;
  late final TextEditingController _difficulty;
  late final TextEditingController _points;
  late List<_EditableOption> _options;

  @override
  void initState() {
    super.initState();
    final exercise = widget.exercise;
    _uiType = exercise?.uiType ?? 'multiple_choice';
    _question = TextEditingController(text: exercise?.question);
    _correctAnswer = TextEditingController(text: exercise?.correctAnswer);
    _explanation = TextEditingController(text: exercise?.explanation);
    _hint = TextEditingController(text: exercise?.hint);
    _audioUrl = TextEditingController(text: exercise?.audioUrl);
    _imageUrl = TextEditingController(text: exercise?.imageUrl);
    _difficulty = TextEditingController(text: '${exercise?.difficulty ?? 1}');
    _points = TextEditingController(text: '${exercise?.points ?? 10}');
    _options = (exercise?.options ?? const <ExerciseOption>[])
        .map(_EditableOption.fromModel)
        .toList();
    if (_choiceTypes.contains(_uiType) && _options.isEmpty) {
      _options = [_EditableOption(), _EditableOption()];
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _question,
      _correctAnswer,
      _explanation,
      _hint,
      _audioUrl,
      _imageUrl,
      _difficulty,
      _points,
    ]) {
      controller.dispose();
    }
    for (final option in _options) {
      option.dispose();
    }
    super.dispose();
  }

  String? _required(String? value) =>
      value == null || value.trim().isEmpty ? 'Required' : null;

  String? _positiveInteger(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 0 ? 'Enter 0 or more' : null;
  }

  String? _difficultyValidator(String? value) {
    final parsed = int.tryParse(value ?? '');
    return parsed == null || parsed < 1 || parsed > 5
        ? 'Enter 1 to 5'
        : null;
  }

  void _changeType(String value) {
    setState(() {
      _uiType = value;
      if (_choiceTypes.contains(value) && _options.isEmpty) {
        _options = [_EditableOption(), _EditableOption()];
      }
    });
  }

  void _addOption() => setState(() => _options.add(_EditableOption()));

  void _removeOption(int index) {
    setState(() => _options.removeAt(index).dispose());
  }

  void _toggleCorrect(int index, bool selected) {
    setState(() => _options[index].isCorrect = selected);
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    if (_choiceTypes.contains(_uiType)) {
      final correct = _options.where((option) => option.isCorrect).toList();
      if (_options.isEmpty || correct.length != 1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Select exactly one correct option.')),
        );
        return;
      }
      _correctAnswer.text = correct.single.text.text.trim();
    }
    final options = _choiceTypes.contains(_uiType)
        ? List.generate(
            _options.length,
            (index) => ExerciseOption(
              id: index.toString(),
              text: _options[index].text.text.trim(),
              isCorrect: _options[index].isCorrect,
            ),
          )
        : null;
    Navigator.pop(
      context,
      Exercise(
        id: widget.exercise?.id ??
            'ex_${DateTime.now().microsecondsSinceEpoch}',
        type: _uiTypeToType[_uiType] ?? _uiType,
        uiType: _uiType,
        question: _question.text.trim(),
        options: options,
        correctAnswer: _correctAnswer.text.trim(),
        explanation: _nullable(_explanation.text),
        hint: _nullable(_hint.text),
        audioUrl: _nullable(_audioUrl.text),
        imageUrl: _nullable(_imageUrl.text),
        difficulty: int.parse(_difficulty.text),
        points: int.parse(_points.text),
      ),
    );
  }

  String? _nullable(String value) =>
      value.trim().isEmpty ? null : value.trim();

  @override
  Widget build(BuildContext context) {
    final showOptions = _choiceTypes.contains(_uiType);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        leading: IconButton(
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close),
        ),
        title: Text(
          widget.exercise == null ? 'Add exercise' : 'Edit exercise',
          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: FilledButton(onPressed: _submit, child: const Text('Done')),
          ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
          children: [
            DropdownButtonFormField<String>(
              initialValue: _uiType,
              decoration: const InputDecoration(labelText: 'Exercise type'),
              items: _uiTypeLabels.entries
                  .map((entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ))
                  .toList(),
              onChanged: (value) {
                if (value != null) _changeType(value);
              },
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _question,
              label: 'Question / prompt',
              maxLines: 3,
              validator: _required,
            ),
            if (showOptions) ...[
              const SizedBox(height: 20),
              Text(
                'Options',
                style: GoogleFonts.spaceGrotesk(
                  color: AppColors.onSurface,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              ...List.generate(_options.length, (index) {
                final option = _options[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Checkbox(
                        value: option.isCorrect,
                        onChanged: (value) =>
                            _toggleCorrect(index, value ?? false),
                      ),
                      Expanded(
                        child: TextFormField(
                          controller: option.text,
                          decoration: InputDecoration(
                            labelText: 'Option ${index + 1}',
                          ),
                          validator: _required,
                        ),
                      ),
                      IconButton(
                        constraints:
                            const BoxConstraints(minWidth: 48, minHeight: 48),
                        tooltip: 'Remove option',
                        color: AppColors.error,
                        onPressed: () => _removeOption(index),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                    ],
                  ),
                );
              }),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _addOption,
                  icon: const Icon(Icons.add),
                  label: const Text('Add option'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _Field(
              controller: _correctAnswer,
              label: 'Correct answer',
              validator: _required,
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _explanation,
              label: 'Explanation',
              maxLines: 2,
            ),
            const SizedBox(height: 16),
            _Field(controller: _hint, label: 'Hint'),
            const SizedBox(height: 16),
            _Field(
              controller: _audioUrl,
              label: 'Audio URL',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            _Field(
              controller: _imageUrl,
              label: 'Image URL',
              keyboardType: TextInputType.url,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _Field(
                    controller: _difficulty,
                    label: 'Difficulty',
                    keyboardType: TextInputType.number,
                    validator: _difficultyValidator,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _Field(
                    controller: _points,
                    label: 'Points',
                    keyboardType: TextInputType.number,
                    validator: _positiveInteger,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _EditableOption {
  final TextEditingController text;
  bool isCorrect;

  _EditableOption({String text = '', this.isCorrect = false})
      : text = TextEditingController(text: text);

  factory _EditableOption.fromModel(ExerciseOption option) => _EditableOption(
        text: option.text,
        isCorrect: option.isCorrect,
      );

  void dispose() => text.dispose();
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;

  const _Field({
    required this.controller,
    required this.label,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
  });

  @override
  Widget build(BuildContext context) => TextFormField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        validator: validator,
        decoration: InputDecoration(labelText: label),
      );
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final VoidCallback? onRetry;

  const _ErrorBanner({required this.message, this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: GoogleFonts.spaceGrotesk(color: AppColors.error),
              ),
            ),
            if (onRetry != null)
              TextButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      );
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;

  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 56),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.outline),
        ),
        child: Column(
          children: [
            const Icon(
              Icons.quiz_outlined,
              size: 48,
              color: AppColors.onSurfaceMuted,
            ),
            const SizedBox(height: 12),
            Text(
              'No exercises yet',
              style: GoogleFonts.spaceGrotesk(
                color: AppColors.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add),
              label: const Text('Add exercise'),
            ),
          ],
        ),
      );
}
