import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../shared/widgets/growth_form.dart';
import '../data/gamification_repository.dart';

const achievementCategories = [
  'lessons',
  'streak',
  'vocabulary',
  'xp',
  'quiz',
  'course',
  'voice',
  'level',
  'special',
  'skill',
  'social',
  'milestone',
];

const _conditions = [
  'lesson_complete',
  'reach_streak',
  'vocab_mastered',
  'xp_earned',
  'perfect_score',
  'first_perfect',
  'course_complete',
  'voice_practice',
  'numeric_level',
  'study_time_night',
  'study_time_morning',
  'speed_lesson',
  'grammar_mastered',
  'culture_lesson',
  'writing_complete',
  'listening_complete',
  'social_interaction',
  'chat_complete',
  'help_others',
  'daily_challenge_complete',
  'comeback',
];
const _rarities = ['common', 'rare', 'epic', 'legendary'];

class AchievementForm extends StatefulWidget {
  const AchievementForm({super.key, this.item, required this.repository});

  final AchievementItem? item;
  final GamificationRepository repository;

  @override
  State<AchievementForm> createState() => _AchievementFormState();
}

class _AchievementFormState extends State<AchievementForm> {
  late final TextEditingController _name,
      _description,
      _icon,
      _color,
      _conditionValue,
      _xp,
      _gems;
  late String _condition, _category, _rarity;
  late bool _hidden;
  bool _saving = false, _submitted = false;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name);
    _description = TextEditingController(text: i?.description);
    _icon = TextEditingController(text: i?.badgeIcon);
    _color = TextEditingController(text: i?.badgeColor ?? '#4CAF50');
    _conditionValue = TextEditingController(text: '${i?.conditionValue ?? 1}');
    _xp = TextEditingController(text: '${i?.xpReward ?? 0}');
    _gems = TextEditingController(text: '${i?.gemsReward ?? 0}');
    _condition = i != null && _conditions.contains(i.conditionType)
        ? i.conditionType
        : _conditions.first;
    _category = i != null && achievementCategories.contains(i.category)
        ? i.category
        : achievementCategories.first;
    _rarity = i != null && _rarities.contains(i.rarity)
        ? i.rarity
        : _rarities.first;
    _hidden = i?.isHidden ?? false;
  }

  @override
  void dispose() {
    for (final c in [
      _name,
      _description,
      _icon,
      _color,
      _conditionValue,
      _xp,
      _gems,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(TextEditingController c) =>
      _submitted && c.text.trim().isEmpty
      ? 'adminGrowth.gamify.required'.tr()
      : null;

  String? _int(TextEditingController c) =>
      _submitted && int.tryParse(c.text.trim()) == null
      ? 'adminGrowth.gamify.badNumber'.tr()
      : null;

  Future<void> _save() async {
    setState(() => _submitted = true);
    if (_name.text.trim().isEmpty ||
        _description.text.trim().isEmpty ||
        int.tryParse(_conditionValue.text.trim()) == null ||
        int.tryParse(_xp.text.trim()) == null ||
        int.tryParse(_gems.text.trim()) == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.repository.saveAchievement(widget.item?.id, {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'badge_icon': _icon.text.trim(),
        'badge_color': _color.text.trim(),
        'condition_type': _condition,
        'condition_value': int.parse(_conditionValue.text.trim()),
        'category': _category,
        'rarity': _rarity,
        'xp_reward': int.parse(_xp.text.trim()),
        'gems_reward': int.parse(_gems.text.trim()),
        'is_hidden': _hidden,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final api = AdminApiError.from(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            api.isForbidden
                ? api.message.resolve()
                : 'adminGrowth.common.saveFailed'.tr(),
          ),
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => GrowthFormSheet(
    title: widget.item == null
        ? 'adminGrowth.gamify.newAchievement'.tr()
        : 'adminGrowth.gamify.editAchievement'.tr(),
    saving: _saving,
    onSave: _save,
    children: [
      GrowthField(
        controller: _name,
        label: 'adminGrowth.gamify.name'.tr(),
        errorText: _required(_name),
      ),
      GrowthField(
        controller: _description,
        label: 'adminGrowth.gamify.description'.tr(),
        lines: 2,
        errorText: _required(_description),
      ),
      GrowthField(
        controller: _icon,
        label: 'adminGrowth.gamify.badgeIcon'.tr(),
      ),
      GrowthField(
        controller: _color,
        label: 'adminGrowth.gamify.badgeColor'.tr(),
      ),
      GrowthDropdown(
        label: 'adminGrowth.gamify.condition'.tr(),
        value: _condition,
        options: _conditions,
        onChanged: (v) => setState(() => _condition = v),
      ),
      GrowthField(
        controller: _conditionValue,
        label: 'adminGrowth.gamify.conditionValue'.tr(),
        number: true,
        errorText: _int(_conditionValue),
      ),
      GrowthDropdown(
        label: 'adminGrowth.gamify.category'.tr(),
        value: _category,
        options: achievementCategories,
        onChanged: (v) => setState(() => _category = v),
      ),
      GrowthDropdown(
        label: 'adminGrowth.gamify.rarity'.tr(),
        value: _rarity,
        options: _rarities,
        onChanged: (v) => setState(() => _rarity = v),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GrowthField(
              controller: _xp,
              label: 'adminGrowth.gamify.xpReward'.tr(),
              number: true,
              errorText: _int(_xp),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: GrowthField(
              controller: _gems,
              label: 'adminGrowth.gamify.gemReward'.tr(),
              number: true,
              errorText: _int(_gems),
            ),
          ),
        ],
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('adminGrowth.gamify.hidden'.tr()),
        value: _hidden,
        onChanged: (v) => setState(() => _hidden = v),
      ),
    ],
  );
}
