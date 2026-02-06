import 'package:flutter/material.dart';

import '../../data/models/educational_hints_model.dart';

/// Educational Hints Card
/// Displays grammar corrections and vocabulary hints from AI response
class EducationalHintsCard extends StatelessWidget {
  final EducationalHints hints;

  const EducationalHintsCard({super.key, required this.hints});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.75,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Grammar corrections
          if (hints.grammarCorrections.isNotEmpty)
            ...hints.grammarCorrections.map(
              (correction) => GrammarCorrectionBadge(correction: correction),
            ),

          // Vocabulary hints
          if (hints.vocabularyHints.isNotEmpty)
            ...hints.vocabularyHints.map(
              (hint) => VocabularyHintCard(hint: hint),
            ),

          // Encouragement
          if (hints.encouragement != null && hints.encouragement!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.thumb_up, size: 14, color: Colors.green),
                  const SizedBox(width: 4),
                  Flexible(
                    child: Text(
                      hints.encouragement!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Grammar Correction Badge
/// Shows original error and corrected version
class GrammarCorrectionBadge extends StatelessWidget {
  final GrammarCorrection correction;

  const GrammarCorrectionBadge({super.key, required this.correction});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Icon(Icons.edit_note, size: 16, color: Colors.orange.shade700),
              const SizedBox(width: 4),
              Text(
                'Grammar Correction',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.orange.shade700,
                ),
              ),
              if (correction.errorType != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      correction.errorType!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orange.shade800,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Original vs Corrected
          if (correction.original.isNotEmpty)
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Original (struck through)
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.close, size: 14, color: Colors.red.shade400),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            correction.original,
                            style: TextStyle(
                              decoration: TextDecoration.lineThrough,
                              color: Colors.red.shade700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Icon(Icons.arrow_forward, size: 16),
                ),
                // Corrected
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.check, size: 14, color: Colors.green.shade600),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            correction.corrected,
                            style: TextStyle(
                              color: Colors.green.shade700,
                              fontWeight: FontWeight.w500,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          // Explanation
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.lightbulb, size: 14, color: Colors.amber.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    correction.explanation,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),

          // Rule name
          if (correction.rule != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Rule: ${correction.rule}',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade600,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Vocabulary Hint Card
/// Shows vocabulary definition and example
class VocabularyHintCard extends StatelessWidget {
  final VocabularyHint hint;

  const VocabularyHintCard({super.key, required this.hint});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with term
          Row(
            children: [
              Icon(Icons.book, size: 16, color: Colors.blue.shade700),
              const SizedBox(width: 4),
              Expanded(
                child: Row(
                  children: [
                    Text(
                      hint.term,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Colors.blue.shade700,
                      ),
                    ),
                    if (hint.partOfSpeech != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade100,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            hint.partOfSpeech!,
                            style: TextStyle(
                              fontSize: 10,
                              color: Colors.blue.shade800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // Pronunciation
              if (hint.pronunciation != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    hint.pronunciation!,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.blue.shade600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Definition
          Text(
            hint.definition,
            style: const TextStyle(fontSize: 13),
          ),

          // Example
          if (hint.example != null && hint.example!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('📝 ', style: TextStyle(fontSize: 12)),
                    Expanded(
                      child: Text(
                        hint.example!,
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                          color: Colors.grey.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Topic Progress Indicator
/// Shows progress in the current topic conversation
class TopicProgressIndicator extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final String? stepLabel;

  const TopicProgressIndicator({
    super.key,
    required this.currentStep,
    required this.totalSteps,
    this.stepLabel,
  });

  @override
  Widget build(BuildContext context) {
    final progress = totalSteps > 0 ? currentStep / totalSteps : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).primaryColor.withOpacity(0.1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                stepLabel ?? 'Progress',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
              Text(
                '$currentStep / $totalSteps',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: Colors.grey.shade200,
            ),
          ),
        ],
      ),
    );
  }
}

/// Expandable hints toggle
/// Small button to show/hide educational hints
class ExpandableHintsToggle extends StatefulWidget {
  final EducationalHints hints;

  const ExpandableHintsToggle({super.key, required this.hints});

  @override
  State<ExpandableHintsToggle> createState() => _ExpandableHintsToggleState();
}

class _ExpandableHintsToggleState extends State<ExpandableHintsToggle> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final totalHints = widget.hints.grammarCorrections.length +
        widget.hints.vocabularyHints.length;

    if (totalHints == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Toggle button
        InkWell(
          onTap: () => setState(() => _isExpanded = !_isExpanded),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.purple.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.purple.shade200),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.school,
                  size: 14,
                  color: Colors.purple.shade600,
                ),
                const SizedBox(width: 4),
                Text(
                  '$totalHints Learning Hint${totalHints > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.purple.shade700,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _isExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: Colors.purple.shade600,
                ),
              ],
            ),
          ),
        ),

        // Expanded hints
        if (_isExpanded)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: EducationalHintsCard(hints: widget.hints),
          ),
      ],
    );
  }
}
