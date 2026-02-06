/// Badge Asset Demo Screen - Preview all badge image assets
/// Shows which badges have image files and which need to be created

import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/achievements/data/badge_asset_mapper.dart';

class BadgeAssetDemoScreen extends StatelessWidget {
  const BadgeAssetDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Badge Assets Preview'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildInfoCard(context),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '✅ Lesson Badges (4/4)',
            [
              ('first_steps', 'First Steps', 'common-lesson.png'),
              ('dedicated_learner', 'Dedicated Learner', 'common-lesson.png'),
              ('knowledge_seeker', 'Knowledge Seeker', 'rare-lesson.png'),
              ('scholar', 'Scholar', 'epic-lesson.png'),
              ('professor', 'Professor', 'legendary-lesson.png'),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '✅ Vocabulary Badges (4/4)',
            [
              ('word_collector', 'Word Collector', 'common-vocabulary.png'),
              ('vocab_builder', 'Vocab Builder', 'rare-vocabulary.png'),
              ('vocab_master', 'Vocab Master', 'epic-vocabulary.png'),
              ('walking_dictionary', 'Walking Dictionary', 'legendary-vocabulary.png'),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '⚠️ Streak Badges (4/6)',
            [
              ('getting_started', '3 Days', 'streak3.png'),
              ('week_warrior', '7 Days', 'streak7.png'),
              ('two_weeks_strong', '14 Days', 'streak14.png', false),
              ('month_master', '30 Days', 'streak30.png'),
              ('quarterly_champion', '90 Days', 'streak90.png', false),
              ('year_legend', '365 Days', 'streak365.png'),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '❌ XP Badges (0/4)',
            [
              ('xp_hunter', '100 XP', 'xp-100.png', false),
              ('xp_warrior', '500 XP', 'xp-500.png', false),
              ('xp_champion', '1000 XP', 'xp-1000.png', false),
              ('xp_legend', '5000 XP', 'xp-5000.png', false),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '⚠️ Perfect Score (1/3)',
            [
              ('perfectionist', 'Perfect Score', '100%.png'),
              ('perfect_10', 'Perfect 10', 'perfect-10.png', false),
              ('flawless', 'Flawless 50', 'perfect-50.png', false),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '❌ Course Badges (0/2)',
            [
              ('graduate', 'Graduate', 'course-graduate.png', false),
              ('multi_course_master', 'Course Master', 'course-master.png', false),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '❌ Voice Badges (0/2)',
            [
              ('voice_starter', 'Voice Starter', 'voice-starter.png', false),
              ('voice_pro', 'Voice Pro', 'voice-pro.png', false),
            ],
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            '✅ Special Badges (1/1)',
            [
              ('night_owl', 'Night Owl', 'moon.png'),
            ],
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: Colors.blue.shade700),
                const SizedBox(width: 8),
                Text(
                  'Badge Assets Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue.shade700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _buildStatusRow('✅ Available', '14 badges', Colors.green),
            const SizedBox(height: 4),
            _buildStatusRow('❌ Need to create', '13 badges', Colors.red),
            const SizedBox(height: 4),
            _buildStatusRow('📊 Total', '27 badges', Colors.blue.shade700),
            const SizedBox(height: 12),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              '📝 See docs/BADGE_FILES_REQUIRED.md for full list and AI prompts',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.blue.shade700,
                fontStyle: FontStyle.italic,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusRow(String label, String value, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: color, fontWeight: FontWeight.w500)),
        Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    List<(String id, String name, String filename, [bool exists])> badges,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: badges
              .map((badge) => _buildBadgePreview(
                    context,
                    badge.$1,
                    badge.$2,
                    badge.$3,
                    badge.length > 3 ? badge.$4 : true,
                  ))
              .toList(),
        ),
      ],
    );
  }

  Widget _buildBadgePreview(
    BuildContext context,
    String id,
    String name,
    String filename,
    bool exists,
  ) {
    final assetPath = 'assets/badges/$filename';

    return Container(
      width: 100,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        border: Border.all(
          color: exists ? Colors.green.shade300 : Colors.red.shade300,
          width: 2,
        ),
        borderRadius: BorderRadius.circular(12),
        color: exists ? Colors.green.shade50 : Colors.red.shade50,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Badge preview or placeholder
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.grey.shade200,
            ),
            child: exists
                ? ClipOval(
                    child: Image.asset(
                      assetPath,
                      width: 64,
                      height: 64,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Icon(Icons.broken_image, size: 32, color: Colors.grey);
                      },
                    ),
                  )
                : Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 32,
                    color: Colors.grey.shade400,
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            name,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            filename,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.grey.shade600,
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: exists ? Colors.green : Colors.red,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              exists ? '✓' : '✗',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
