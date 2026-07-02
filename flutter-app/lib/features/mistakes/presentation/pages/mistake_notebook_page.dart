import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

enum _MistakeFilter { all, unreviewed, reviewed }

class MistakeNotebookPage extends StatefulWidget {
  final MistakeNotebookRepository repository;

  const MistakeNotebookPage({
    super.key,
    this.repository = const MistakeNotebookRepository(),
  });

  @override
  State<MistakeNotebookPage> createState() => _MistakeNotebookPageState();
}

class _MistakeNotebookPageState extends State<MistakeNotebookPage> {
  List<MistakeNotebookEntry> _entries = const [];
  _MistakeFilter _filter = _MistakeFilter.all;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadEntries();
  }

  Future<void> _loadEntries() async {
    setState(() => _isLoading = true);
    final entries = await widget.repository.getEntries();
    if (!mounted) return;
    setState(() {
      _entries = entries;
      _isLoading = false;
    });
  }

  Future<void> _markReviewed(String id) async {
    await widget.repository.markReviewed(id);
    await _loadEntries();
  }

  Future<void> _deleteEntry(MistakeNotebookEntry entry) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('mistakeNotebook.deleteTitle'.tr()),
        content: Text('mistakeNotebook.deleteMessage'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text('common.cancel'.tr()),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text('mistakeNotebook.delete'.tr()),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    await widget.repository.delete(entry.id);
    await _loadEntries();
  }

  List<MistakeNotebookEntry> get _filteredEntries {
    return switch (_filter) {
      _MistakeFilter.all => _entries,
      _MistakeFilter.unreviewed =>
        _entries.where((entry) => !entry.isReviewed).toList(growable: false),
      _MistakeFilter.reviewed =>
        _entries.where((entry) => entry.isReviewed).toList(growable: false),
    };
  }

  int get _unreviewedCount =>
      _entries.where((entry) => !entry.isReviewed).length;

  int get _reviewedCount => _entries.where((entry) => entry.isReviewed).length;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('mistakeNotebook.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr(),
            onPressed: _loadEntries,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadEntries,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  _NotebookHeader(
                    total: _entries.length,
                    unreviewed: _unreviewedCount,
                    reviewed: _reviewedCount,
                  ),
                  const SizedBox(height: 14),
                  _FilterRow(
                    selected: _filter,
                    onChanged: (filter) => setState(() => _filter = filter),
                  ),
                  const SizedBox(height: 14),
                  if (_filteredEntries.isEmpty)
                    _NotebookEmptyState(hasAnyEntry: _entries.isNotEmpty)
                  else
                    for (final entry in _filteredEntries) ...[
                      _MistakeCard(
                        entry: entry,
                        onMarkReviewed: () => _markReviewed(entry.id),
                        onDelete: () => _deleteEntry(entry),
                      ),
                      const SizedBox(height: 12),
                    ],
                ],
              ),
            ),
    );
  }
}

class _NotebookHeader extends StatelessWidget {
  const _NotebookHeader({
    required this.total,
    required this.unreviewed,
    required this.reviewed,
  });

  final int total;
  final int unreviewed;
  final int reviewed;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = AppColorRoles.primary(isDark);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.slate200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: isDark ? 0.2 : 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(Icons.rule_folder_rounded, color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'mistakeNotebook.heroTitle'.tr(),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'mistakeNotebook.heroSubtitle'.tr(),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _HeaderMetric(
                  value: '$total',
                  label: 'mistakeNotebook.total'.tr(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMetric(
                  value: '$unreviewed',
                  label: 'mistakeNotebook.toReview'.tr(),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeaderMetric(
                  value: '$reviewed',
                  label: 'mistakeNotebook.reviewed'.tr(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeaderMetric extends StatelessWidget {
  const _HeaderMetric({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkInput : AppColors.grey50,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterRow extends StatelessWidget {
  const _FilterRow({required this.selected, required this.onChanged});

  final _MistakeFilter selected;
  final ValueChanged<_MistakeFilter> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _FilterChipButton(
          label: 'mistakeNotebook.filterAll'.tr(),
          selected: selected == _MistakeFilter.all,
          onSelected: () => onChanged(_MistakeFilter.all),
        ),
        _FilterChipButton(
          label: 'mistakeNotebook.filterToReview'.tr(),
          selected: selected == _MistakeFilter.unreviewed,
          onSelected: () => onChanged(_MistakeFilter.unreviewed),
        ),
        _FilterChipButton(
          label: 'mistakeNotebook.filterReviewed'.tr(),
          selected: selected == _MistakeFilter.reviewed,
          onSelected: () => onChanged(_MistakeFilter.reviewed),
        ),
      ],
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontWeight: FontWeight.w700,
        color: selected ? Colors.white : null,
      ),
      selectedColor: AppColorRoles.primary(
        Theme.of(context).brightness == Brightness.dark,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    );
  }
}

class _NotebookEmptyState extends StatelessWidget {
  const _NotebookEmptyState({required this.hasAnyEntry});

  final bool hasAnyEntry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.slate200,
        ),
      ),
      child: Column(
        children: [
          Icon(
            hasAnyEntry
                ? Icons.check_circle_rounded
                : Icons.auto_stories_rounded,
            size: 42,
            color: hasAnyEntry
                ? AppColors.greenSuccessBright
                : AppColorRoles.primary(isDark),
          ),
          const SizedBox(height: 12),
          Text(
            hasAnyEntry
                ? 'mistakeNotebook.emptyFilterTitle'.tr()
                : 'mistakeNotebook.emptyTitle'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            hasAnyEntry
                ? 'mistakeNotebook.emptyFilterSubtitle'.tr()
                : 'mistakeNotebook.emptySubtitle'.tr(),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _MistakeCard extends StatelessWidget {
  const _MistakeCard({
    required this.entry,
    required this.onMarkReviewed,
    required this.onDelete,
  });

  final MistakeNotebookEntry entry;
  final VoidCallback onMarkReviewed;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sourceLabel = _sourceLabel(entry.sourceType);
    final dateText = DateFormat.yMMMd().format(entry.createdAt);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: entry.isReviewed
              ? AppColors.greenSuccessBright.withValues(alpha: 0.4)
              : AppColors.errorBright.withValues(alpha: isDark ? 0.45 : 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sourceLabel,
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: AppColorRoles.primary(isDark),
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      entry.sourceTitle.isEmpty
                          ? sourceLabel
                          : entry.sourceTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: AppColorRoles.textSecondary(isDark),
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                dateText,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColorRoles.textSecondary(isDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            entry.question,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          _AnswerLine(
            icon: Icons.close_rounded,
            iconColor: AppColors.errorBright,
            label: 'mistakeNotebook.yourAnswer'.tr(),
            value: entry.selectedAnswer,
          ),
          const SizedBox(height: 8),
          _AnswerLine(
            icon: Icons.check_rounded,
            iconColor: AppColors.greenSuccessBright,
            label: 'mistakeNotebook.correctAnswer'.tr(),
            value: entry.correctAnswer,
          ),
          if (entry.explanation.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'mistakeNotebook.explanation'.tr(),
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              entry.explanation,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
                height: 1.35,
              ),
            ),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              if (entry.isReviewed)
                _ReviewedPill(reviewCount: entry.reviewCount)
              else
                OutlinedButton.icon(
                  onPressed: onMarkReviewed,
                  icon: const Icon(Icons.done_rounded, size: 18),
                  label: Text('mistakeNotebook.markReviewed'.tr()),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'mistakeNotebook.delete'.tr(),
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _sourceLabel(String sourceType) {
    return switch (sourceType) {
      'book_quiz' => 'mistakeNotebook.sourceBookQuiz'.tr(),
      'news_quiz' => 'mistakeNotebook.sourceNewsQuiz'.tr(),
      'game_fill_blank' => 'mistakeNotebook.sourceFillBlank'.tr(),
      'game_grammar_quiz' => 'mistakeNotebook.sourceGrammarQuiz'.tr(),
      _ => 'mistakeNotebook.sourceQuiz'.tr(),
    };
  }
}

class _AnswerLine extends StatelessWidget {
  const _AnswerLine({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: iconColor, size: 18),
        const SizedBox(width: 8),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
                height: 1.35,
              ),
              children: [
                TextSpan(
                  text: '$label: ',
                  style: TextStyle(
                    color: AppColorRoles.textPrimary(isDark),
                    fontWeight: FontWeight.w800,
                  ),
                ),
                TextSpan(text: value.isEmpty ? '-' : value),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReviewedPill extends StatelessWidget {
  const _ReviewedPill({required this.reviewCount});

  final int reviewCount;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.greenSuccessBright.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: AppColors.greenSuccessBright,
            size: 16,
          ),
          const SizedBox(width: 6),
          Text(
            reviewCount > 1
                ? 'mistakeNotebook.reviewedTimes'.tr(
                    namedArgs: {'count': '$reviewCount'},
                  )
                : 'mistakeNotebook.reviewed'.tr(),
            style: const TextStyle(
              color: AppColors.greenSuccessBright,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
