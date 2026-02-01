import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/voice/domain/entities/pronunciation_score.dart';

/// Pronunciation Score Card Widget
/// Displays the result of pronunciation assessment
class PronunciationScoreCard extends StatelessWidget {
  final PronunciationScore score;
  final VoidCallback? onTryAgain;
  final VoidCallback? onListenExample;

  const PronunciationScoreCard({
    super.key,
    required this.score,
    this.onTryAgain,
    this.onListenExample,
  });

  Color _getScoreColor(int value) {
    if (value >= 90) return Colors.green;
    if (value >= 70) return Colors.amber;
    if (value >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Overall Score
          _OverallScoreCircle(
            score: score.overallScore,
            grade: score.grade,
          ),
          const SizedBox(height: 16),
          
          // Feedback
          if (score.feedback != null) ...[
            Text(
              score.feedback!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _getScoreColor(score.overallScore),
                    fontWeight: FontWeight.w500,
                  ),
            ),
            const SizedBox(height: 20),
          ],
          
          // Detail Scores
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _ScoreItem(
                label: 'Accuracy',
                score: score.accuracyScore,
                icon: Icons.check_circle_outline,
              ),
              _ScoreItem(
                label: 'Fluency',
                score: score.fluencyScore,
                icon: Icons.speed,
              ),
              _ScoreItem(
                label: 'Completeness',
                score: score.completenessScore,
                icon: Icons.format_list_numbered,
              ),
            ],
          ),
          
          // Word breakdown
          if (score.wordScores.isNotEmpty) ...[
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            Text(
              'Word Breakdown',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: score.wordScores.map((ws) => _WordChip(wordScore: ws)).toList(),
            ),
          ],
          
          // Action buttons
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (onListenExample != null)
                OutlinedButton.icon(
                  onPressed: onListenExample,
                  icon: const Icon(Icons.volume_up, size: 18),
                  label: const Text('Listen'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              if (onListenExample != null && onTryAgain != null)
                const SizedBox(width: 12),
              if (onTryAgain != null)
                ElevatedButton.icon(
                  onPressed: onTryAgain,
                  icon: const Icon(Icons.refresh, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OverallScoreCircle extends StatelessWidget {
  final int score;
  final String grade;

  const _OverallScoreCircle({required this.score, required this.grade});

  Color _getColor() {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.amber;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: 100,
          height: 100,
          child: CircularProgressIndicator(
            value: score / 100,
            strokeWidth: 8,
            backgroundColor: Colors.grey.shade200,
            valueColor: AlwaysStoppedAnimation<Color>(_getColor()),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$score',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getColor(),
                  ),
            ),
            Text(
              grade,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: _getColor(),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ScoreItem extends StatelessWidget {
  final String label;
  final int score;
  final IconData icon;

  const _ScoreItem({
    required this.label,
    required this.score,
    required this.icon,
  });

  Color _getColor() {
    if (score >= 90) return Colors.green;
    if (score >= 70) return Colors.amber;
    if (score >= 50) return Colors.orange;
    return Colors.red;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: _getColor(), size: 24),
        const SizedBox(height: 4),
        Text(
          '$score%',
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: _getColor(),
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: AppColors.textGrey,
              ),
        ),
      ],
    );
  }
}

class _WordChip extends StatelessWidget {
  final WordScore wordScore;

  const _WordChip({required this.wordScore});

  Color _getColor(BuildContext context) {
    if (wordScore.score >= 90) return Colors.green.shade100;
    if (wordScore.score >= 70) return Colors.amber.shade100;
    if (wordScore.score >= 50) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  Color _getTextColor() {
    if (wordScore.score >= 90) return Colors.green.shade800;
    if (wordScore.score >= 70) return Colors.amber.shade800;
    if (wordScore.score >= 50) return Colors.orange.shade800;
    return Colors.red.shade800;
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: wordScore.hasIssue ? wordScore.issue! : 'Good',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: _getColor(context),
          borderRadius: BorderRadius.circular(16),
          border: wordScore.hasIssue
              ? Border.all(color: _getTextColor().withOpacity(0.5))
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              wordScore.word,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: _getTextColor(),
                    fontWeight: FontWeight.w500,
                  ),
            ),
            if (wordScore.hasIssue) ...[
              const SizedBox(width: 4),
              Icon(
                _getIssueIcon(wordScore.issue!),
                size: 14,
                color: _getTextColor(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  IconData _getIssueIcon(String issue) {
    switch (issue) {
      case 'mispronunciation':
        return Icons.warning_amber_rounded;
      case 'omission':
        return Icons.remove_circle_outline;
      case 'insertion':
        return Icons.add_circle_outline;
      default:
        return Icons.info_outline;
    }
  }
}
