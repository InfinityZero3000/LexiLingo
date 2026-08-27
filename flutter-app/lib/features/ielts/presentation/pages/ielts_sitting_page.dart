import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../../../../core/network/api_config.dart';
import '../../../../core/di/service_locator.dart';
import '../../../voice/data/datasources/voice_remote_datasource.dart';
import '../../domain/entities/ielts_entities.dart';
import '../providers/ielts_provider.dart';
import 'ielts_result_page.dart';

/// One sitting, one skill at a time.
///
/// The four skills are genuinely different surfaces — Listening is an audio
/// player the recording plays once, Reading is a passage beside its questions,
/// Writing is a word-counted composition, Speaking is a recording. A single
/// generic question list would have made all four worse.
class IeltsSittingPage extends StatelessWidget {
  final IeltsTestSummary test;
  const IeltsSittingPage({super.key, required this.test});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<IeltsProvider>(
      create: (_) => sl<IeltsProvider>()..startTest(test.id),
      child: _SittingView(test: test),
    );
  }
}

class _SittingView extends StatefulWidget {
  final IeltsTestSummary test;
  const _SittingView({required this.test});

  @override
  State<_SittingView> createState() => _SittingViewState();
}

class _SittingViewState extends State<_SittingView> {
  int _sectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    // Answers change on every keystroke, so nothing here may watch the whole
    // provider — a full paper is 80 questions and would rebuild all of them.
    final provider = context.read<IeltsProvider>();
    final sections = context.select<IeltsProvider, List<IeltsSection>>(
      (p) => p.paper.sections,
    );
    final isLoading = context.select<IeltsProvider, bool>((p) => p.isLoading);

    if (isLoading && sections.isEmpty) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (sections.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.test.title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              provider.error ?? 'This test has no sections yet.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    final index = _sectionIndex.clamp(0, sections.length - 1);
    final section = sections[index];

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final leave = await _confirmLeave(context);
        if (leave == true && context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(ieltsSkillLabel(section.skill)),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(48),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  for (var i = 0; i < sections.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: 8, bottom: 8),
                      child: ChoiceChip(
                        label: Text(ieltsSkillLabel(sections[i].skill)),
                        selected: i == index,
                        onSelected: (_) => setState(() => _sectionIndex = i),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        body: _SectionBody(section: section),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Expanded(child: _AnsweredCount()),
                if (index < sections.length - 1)
                  FilledButton.tonal(
                    onPressed: () => setState(() => _sectionIndex = index + 1),
                    child: Text('Next: ${ieltsSkillLabel(sections[index + 1].skill)}'),
                  )
                else
                  _SubmitButton(onSubmit: () => _submit(context, provider)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<bool?> _confirmLeave(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Leave the test?'),
        content: const Text(
          'Your answers are saved and you can resume this test later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  Future<void> _submit(BuildContext context, IeltsProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Submit test?'),
        content: Text(
          'You have answered ${provider.answeredCount} items. '
          'Listening and Reading are scored immediately; Writing and Speaking '
          'are graded by AI and take a moment longer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Keep working'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final result = await provider.submit();
    if (!context.mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(provider.error ?? 'Submission failed')),
      );
      return;
    }
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => IeltsResultPage(
          attemptId: result.attemptId,
          existingProvider: provider,
        ),
      ),
    );
  }
}

class _AnsweredCount extends StatelessWidget {
  const _AnsweredCount();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = context.select<IeltsProvider, int>((p) => p.answeredCount);
    return Text(
      '$count answered',
      style: theme.textTheme.bodySmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

class _SubmitButton extends StatelessWidget {
  final VoidCallback onSubmit;
  const _SubmitButton({required this.onSubmit});

  @override
  Widget build(BuildContext context) {
    final submitting =
        context.select<IeltsProvider, bool>((p) => p.isSubmitting);
    return FilledButton(
      onPressed: submitting ? null : onSubmit,
      child: submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Text('Submit test'),
    );
  }
}

class _SectionBody extends StatelessWidget {
  final IeltsSection section;
  const _SectionBody({required this.section});

  @override
  Widget build(BuildContext context) {
    switch (section.skill) {
      case IeltsSkill.listening:
        return _ListeningSection(section: section);
      case IeltsSkill.reading:
        return _ReadingSection(section: section);
      case IeltsSkill.writing:
        return _WritingSection(section: section);
      case IeltsSkill.speaking:
        return _SpeakingSection(section: section);
    }
  }
}

// ---------------------------------------------------------------------------
// Listening
// ---------------------------------------------------------------------------

class _ListeningSection extends StatelessWidget {
  final IeltsSection section;
  const _ListeningSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final part in section.parts) ...[
          Text(
            part.title ?? 'Part ${part.order}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          if (part.audioUrl != null && part.audioUrl!.isNotEmpty)
            _AudioPlayerBar(url: part.audioUrl!),
          if (part.instructions != null) ...[
            const SizedBox(height: 8),
            Text(part.instructions!, style: Theme.of(context).textTheme.bodySmall),
          ],
          const SizedBox(height: 12),
          ...part.groups.map((group) => _QuestionGroup(group: group)),
          const Divider(height: 32),
        ],
      ],
    );
  }
}

class _AudioPlayerBar extends StatefulWidget {
  final String url;
  const _AudioPlayerBar({required this.url});

  @override
  State<_AudioPlayerBar> createState() => _AudioPlayerBarState();
}

class _AudioPlayerBarState extends State<_AudioPlayerBar> {
  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final url = widget.url.startsWith('http')
          ? widget.url
          : '${ApiConfig.mediaBaseUrl}${widget.url}';
      await _player.setUrl(url);
      if (mounted) setState(() => _ready = true);
    } catch (e) {
      if (mounted) setState(() => _error = 'Audio unavailable');
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_error != null) {
      return Card(
        color: theme.colorScheme.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Text(_error!),
        ),
      );
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: StreamBuilder<PlayerState>(
          stream: _player.playerStateStream,
          builder: (context, snapshot) {
            final playing = snapshot.data?.playing ?? false;
            return Row(
              children: [
                IconButton(
                  icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                  onPressed: !_ready
                      ? null
                      : () => playing ? _player.pause() : _player.play(),
                ),
                Expanded(
                  child: StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, positionSnapshot) {
                      final total = _player.duration ?? Duration.zero;
                      final position = positionSnapshot.data ?? Duration.zero;
                      final value = total.inMilliseconds == 0
                          ? 0.0
                          : position.inMilliseconds / total.inMilliseconds;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(value: value.clamp(0.0, 1.0)),
                          const SizedBox(height: 4),
                          Text(
                            '${_fmt(position)} / ${_fmt(total)}',
                            style: theme.textTheme.labelSmall,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                const SizedBox(width: 8),
              ],
            );
          },
        ),
      ),
    );
  }

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}

// ---------------------------------------------------------------------------
// Reading
// ---------------------------------------------------------------------------

class _ReadingSection extends StatelessWidget {
  final IeltsSection section;
  const _ReadingSection({required this.section});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final part in section.parts) ...[
          if (part.passageTitle != null)
            Text(part.passageTitle!, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (part.passageText != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  part.passageText!,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.6),
                ),
              ),
            ),
          const SizedBox(height: 16),
          ...part.groups.map((group) => _QuestionGroup(group: group)),
          const Divider(height: 32),
        ],
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared question rendering
// ---------------------------------------------------------------------------

class _QuestionGroup extends StatelessWidget {
  final IeltsQuestionGroup group;
  const _QuestionGroup({required this.group});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (group.instructions != null && group.instructions!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              group.instructions!,
              style: theme.textTheme.labelMedium?.copyWith(
                fontStyle: FontStyle.italic,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ...group.questions.map(
          (question) => _QuestionTile(question: question, type: group.questionType),
        ),
      ],
    );
  }
}

class _QuestionTile extends StatelessWidget {
  final IeltsQuestion question;
  final String type;
  const _QuestionTile({required this.question, required this.type});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<IeltsProvider>();
    final current = context.select<IeltsProvider, String?>(
      (p) => p.answerFor(question.key),
    );

    final options = question.options.isNotEmpty
        ? question.options
        : _impliedOptions(type);

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${question.number ?? ''}. ${question.prompt}',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          if (options.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: options
                  .map(
                    (option) => ChoiceChip(
                      label: Text(option),
                      selected: current == option,
                      onSelected: (_) =>
                          provider.setAnswer(question.key, option),
                    ),
                  )
                  .toList(),
            )
          else
            TextFormField(
              initialValue: current,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                hintText: 'Your answer',
              ),
              onChanged: (value) => provider.setAnswer(question.key, value),
            ),
        ],
      ),
    );
  }

  /// True/False/Not Given and Yes/No/Not Given carry their options in the
  /// question type rather than in an `options` list, the way IELTS prints them.
  static List<String> _impliedOptions(String type) {
    switch (type) {
      case 'true_false_notgiven':
        return const ['TRUE', 'FALSE', 'NOT GIVEN'];
      case 'yes_no_notgiven':
        return const ['YES', 'NO', 'NOT GIVEN'];
      default:
        return const [];
    }
  }
}

// ---------------------------------------------------------------------------
// Writing
// ---------------------------------------------------------------------------

class _WritingSection extends StatelessWidget {
  final IeltsSection section;
  const _WritingSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final part in section.parts)
          _WritingTask(part: part),
      ],
    );
  }
}

class _WritingTask extends StatelessWidget {
  final IeltsPart part;
  const _WritingTask({required this.part});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<IeltsProvider>();
    final key = part.partKey ?? 'writing_task_${part.order}';
    final text = context.select<IeltsProvider, String?>(
          (p) => p.answerFor(key),
        ) ??
        '';
    final words = text.trim().isEmpty
        ? 0
        : text.trim().split(RegExp(r'\s+')).length;
    final minimum = part.minWords ?? 150;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          key.replaceAll('_', ' ').toUpperCase(),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(part.prompt ?? '', style: theme.textTheme.bodyMedium),
          ),
        ),
        if (part.imageUrl != null && part.imageUrl!.isNotEmpty) ...[
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: Image.network(
              part.imageUrl!.startsWith('http')
                  ? part.imageUrl!
                  : '${ApiConfig.mediaBaseUrl}${part.imageUrl}',
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          initialValue: text,
          maxLines: 12,
          decoration: InputDecoration(
            border: const OutlineInputBorder(),
            hintText: 'Write your response here…',
            helperText: '$words / $minimum words minimum',
            helperStyle: TextStyle(
              color: words >= minimum
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onChanged: (value) => provider.setAnswer(key, value),
        ),
        const SizedBox(height: 8),
        if (part.suggestedMinutes != null)
          Text(
            'Aim for about ${part.suggestedMinutes} minutes.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        const Divider(height: 32),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Speaking
// ---------------------------------------------------------------------------

class _SpeakingSection extends StatelessWidget {
  final IeltsSection section;
  const _SpeakingSection({required this.section});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final part in section.parts) _SpeakingPart(part: part),
      ],
    );
  }
}

class _SpeakingPart extends StatefulWidget {
  final IeltsPart part;
  const _SpeakingPart({required this.part});

  @override
  State<_SpeakingPart> createState() => _SpeakingPartState();
}

class _SpeakingPartState extends State<_SpeakingPart> {
  final AudioRecorder _recorder = AudioRecorder();
  late final TextEditingController _transcriptController;
  bool _recording = false;
  bool _transcribing = false;
  String? _error;

  String get _key => widget.part.partKey ?? 'speaking_part_${widget.part.order}';

  @override
  void initState() {
    super.initState();
    _transcriptController = TextEditingController(
      text: context.read<IeltsProvider>().answerFor(_key) ?? '',
    );
  }

  @override
  void dispose() {
    _transcriptController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    final provider = context.read<IeltsProvider>();
    if (_recording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() {
        _recording = false;
        _transcribing = path != null;
      });
      if (path == null) return;
      try {
        final bytes = await File(path).readAsBytes();
        final response = await sl<VoiceRemoteDataSource>().transcribeAudio(
          audioData: bytes,
          filename: 'speaking.m4a',
        );
        if (!mounted) return;
        final transcript = (response['text'] ?? response['transcript'])?.toString();
        if (transcript != null && transcript.trim().isNotEmpty) {
          // The transcript is what gets graded, so it stays editable — Whisper
          // mishearing a word must not cost the learner a band.
          _transcriptController.text = transcript.trim();
          provider.setAnswer(_key, transcript.trim());
        } else {
          setState(() => _error = 'Nothing was transcribed. Try again.');
        }
      } catch (e) {
        if (mounted) setState(() => _error = 'Could not transcribe the recording.');
      } finally {
        if (mounted) setState(() => _transcribing = false);
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (mounted) setState(() => _error = 'Microphone permission is required.');
      return;
    }
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/ielts_$_key.m4a';
    await _recorder.start(const RecordConfig(), path: path);
    if (!mounted) return;
    setState(() {
      _recording = true;
      _error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.read<IeltsProvider>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _key.replaceAll('_', ' ').toUpperCase(),
          style: theme.textTheme.labelLarge,
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.part.cueCard ?? widget.part.prompt ?? '',
                  style: theme.textTheme.bodyMedium,
                ),
                if (widget.part.prepSeconds != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'You have ${widget.part.prepSeconds}s to prepare and '
                    '${widget.part.speakSeconds ?? 120}s to speak.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            FilledButton.icon(
              onPressed: _transcribing ? null : _toggle,
              icon: Icon(_recording ? Icons.stop : Icons.mic),
              label: Text(_recording ? 'Stop' : 'Record answer'),
            ),
            const SizedBox(width: 12),
            if (_transcribing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _transcriptController,
          maxLines: 6,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            labelText: 'Transcript (edit if the recording was misheard)',
          ),
          onChanged: (value) => provider.setAnswer(_key, value),
        ),
        const Divider(height: 32),
      ],
    );
  }
}
