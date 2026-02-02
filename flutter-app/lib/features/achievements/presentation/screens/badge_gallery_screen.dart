/// Badge Gallery Screen - Demo and preview all badge styles
///
/// This screen allows viewing all badge shapes, rarities, and categories
/// Useful for designers and developers to preview badge configurations

import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/badge_generator.dart';

class BadgeGalleryScreen extends StatelessWidget {
  const BadgeGalleryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Badge Gallery'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildSection(
            context,
            'Badge Shapes',
            'Different shape styles for badges',
            _buildShapeGallery(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Rarity Levels',
            'Common → Rare → Epic → Legendary',
            _buildRarityGallery(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Achievement Categories',
            'Pre-built templates for common achievements',
            _buildCategoryGallery(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Level Badges',
            'CEFR language proficiency levels',
            _buildLevelGallery(),
          ),
          const SizedBox(height: 24),
          _buildSection(
            context,
            'Locked vs Unlocked',
            'Comparison of locked and unlocked states',
            _buildLockedGallery(),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    String subtitle,
    Widget content,
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
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Colors.grey[600],
          ),
        ),
        const SizedBox(height: 16),
        content,
      ],
    );
  }

  Widget _buildShapeGallery() {
    final shapes = [
      (BadgeShape.circle, 'Circle', Icons.emoji_events),
      (BadgeShape.shield, 'Shield', Icons.shield),
      (BadgeShape.star, 'Star', Icons.star),
      (BadgeShape.hexagon, 'Hexagon', Icons.hexagon),
      (BadgeShape.medal, 'Medal', Icons.military_tech),
      (BadgeShape.diamond, 'Diamond', Icons.diamond),
      (BadgeShape.ribbon, 'Ribbon', Icons.bookmark),
      (BadgeShape.banner, 'Banner', Icons.flag),
    ];

    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: shapes.map((shape) {
        return Column(
          children: [
            GeneratedBadge(
              config: BadgeConfig(
                shape: shape.$1,
                rarity: BadgeRarity.epic,
                icon: shape.$3,
              ),
              size: 70,
            ),
            const SizedBox(height: 8),
            Text(
              shape.$2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildRarityGallery() {
    final rarities = [
      (BadgeRarity.common, 'Common'),
      (BadgeRarity.rare, 'Rare'),
      (BadgeRarity.epic, 'Epic'),
      (BadgeRarity.legendary, 'Legendary'),
    ];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: rarities.map((rarity) {
        return Column(
          children: [
            GeneratedBadge(
              config: BadgeConfig(
                shape: BadgeShape.circle,
                rarity: rarity.$1,
                icon: Icons.star,
              ),
              size: 70,
            ),
            const SizedBox(height: 8),
            Text(
              rarity.$2,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildCategoryGallery() {
    final categories = [
      ('Streak 7 days', AchievementBadgeTemplates.streak(7)),
      ('Streak 30 days', AchievementBadgeTemplates.streak(30)),
      ('Streak 365 days', AchievementBadgeTemplates.streak(365)),
      ('100 Lessons', AchievementBadgeTemplates.lessons(100)),
      ('1000 XP', AchievementBadgeTemplates.xp(1000)),
      ('50 Words', AchievementBadgeTemplates.vocabulary(50)),
      ('30 min Speaking', AchievementBadgeTemplates.speaking(30)),
      ('Course Complete', AchievementBadgeTemplates.course(1)),
      ('Perfect Score', AchievementBadgeTemplates.perfectScore()),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: categories.map((cat) {
        return Column(
          children: [
            GeneratedBadge(
              config: cat.$2,
              size: 65,
            ),
            const SizedBox(height: 6),
            SizedBox(
              width: 70,
              child: Text(
                cat.$1,
                style: const TextStyle(fontSize: 10),
                textAlign: TextAlign.center,
                maxLines: 2,
              ),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildLevelGallery() {
    final levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: levels.map((level) {
        return Column(
          children: [
            GeneratedBadge(
              config: AchievementBadgeTemplates.level(level),
              size: 55,
            ),
            const SizedBox(height: 6),
            Text(
              level,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _buildLockedGallery() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Column(
          children: [
            GeneratedBadge(
              config: const BadgeConfig(
                shape: BadgeShape.shield,
                rarity: BadgeRarity.epic,
                icon: Icons.military_tech,
                isLocked: true,
              ),
              size: 80,
            ),
            const SizedBox(height: 8),
            const Text('Locked', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
        Column(
          children: [
            GeneratedBadge(
              config: const BadgeConfig(
                shape: BadgeShape.shield,
                rarity: BadgeRarity.epic,
                icon: Icons.military_tech,
                isLocked: false,
              ),
              size: 80,
            ),
            const SizedBox(height: 8),
            const Text('Unlocked', style: TextStyle(fontWeight: FontWeight.w500)),
          ],
        ),
      ],
    );
  }
}

/// Badge Preview Dialog - Shows badge configuration options
class BadgePreviewDialog extends StatefulWidget {
  const BadgePreviewDialog({super.key});

  @override
  State<BadgePreviewDialog> createState() => _BadgePreviewDialogState();
}

class _BadgePreviewDialogState extends State<BadgePreviewDialog> {
  BadgeShape _selectedShape = BadgeShape.circle;
  BadgeRarity _selectedRarity = BadgeRarity.rare;
  IconData _selectedIcon = Icons.emoji_events;
  bool _isLocked = false;

  final _icons = [
    Icons.emoji_events,
    Icons.military_tech,
    Icons.star,
    Icons.local_fire_department,
    Icons.bolt,
    Icons.school,
    Icons.workspace_premium,
    Icons.diamond,
    Icons.mic,
    Icons.translate,
  ];

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Badge Preview',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 24),
            // Preview
            GeneratedBadge(
              config: BadgeConfig(
                shape: _selectedShape,
                rarity: _selectedRarity,
                icon: _selectedIcon,
                isLocked: _isLocked,
              ),
              size: 120,
            ),
            const SizedBox(height: 24),
            // Shape selector
            _buildSelector(
              'Shape',
              BadgeShape.values,
              _selectedShape,
              (v) => setState(() => _selectedShape = v),
              (v) => v.name,
            ),
            const SizedBox(height: 12),
            // Rarity selector
            _buildSelector(
              'Rarity',
              BadgeRarity.values,
              _selectedRarity,
              (v) => setState(() => _selectedRarity = v),
              (v) => v.name,
            ),
            const SizedBox(height: 12),
            // Icon selector
            Wrap(
              spacing: 8,
              children: _icons.map((icon) {
                return IconButton(
                  onPressed: () => setState(() => _selectedIcon = icon),
                  icon: Icon(icon),
                  style: IconButton.styleFrom(
                    backgroundColor: _selectedIcon == icon
                        ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
                        : null,
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            // Locked toggle
            SwitchListTile(
              title: const Text('Locked'),
              value: _isLocked,
              onChanged: (v) => setState(() => _isLocked = v),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSelector<T>(
    String label,
    List<T> options,
    T selected,
    Function(T) onSelected,
    String Function(T) getName,
  ) {
    return Row(
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        const Spacer(),
        DropdownButton<T>(
          value: selected,
          items: options.map((o) {
            return DropdownMenuItem(value: o, child: Text(getName(o)));
          }).toList(),
          onChanged: (v) {
            if (v != null) onSelected(v);
          },
        ),
      ],
    );
  }
}
