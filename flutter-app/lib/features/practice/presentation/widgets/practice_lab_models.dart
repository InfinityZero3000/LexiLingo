import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';

enum PracticeLabDestination {
  vocabularyReview,
  voicePractice,
  podcast,
  news,
  games,
  lexi,
  mistakeNotebook,
}

class PracticeLabItem {
  final SkillType skill;
  final String titleKey;
  final String subtitleKey;
  final String actionKey;
  final String estimateKey;
  final IconData icon;
  final Color color;
  final PracticeLabDestination destination;
  final bool recommended;
  final bool premiumOnly;

  const PracticeLabItem({
    required this.skill,
    required this.titleKey,
    required this.subtitleKey,
    required this.actionKey,
    required this.estimateKey,
    required this.icon,
    required this.color,
    required this.destination,
    this.recommended = false,
    this.premiumOnly = false,
  });

  PracticeLabItem copyWith({bool? recommended}) {
    return PracticeLabItem(
      skill: skill,
      titleKey: titleKey,
      subtitleKey: subtitleKey,
      actionKey: actionKey,
      estimateKey: estimateKey,
      icon: icon,
      color: color,
      destination: destination,
      recommended: recommended ?? this.recommended,
      premiumOnly: premiumOnly,
    );
  }
}

/// Where a learner goes to work on a given skill.
///
/// The single source of truth for that question. Today's Plan used to keep its
/// own copy and the two had already drifted — writing sent you to games there
/// and to Lexi here — so both now read this.
PracticeLabDestination practiceDestinationForSkill(SkillType skill) {
  switch (skill) {
    case SkillType.vocabulary:
      return PracticeLabDestination.vocabularyReview;
    case SkillType.grammar:
      return PracticeLabDestination.games;
    case SkillType.reading:
      return PracticeLabDestination.news;
    case SkillType.listening:
      return PracticeLabDestination.podcast;
    case SkillType.speaking:
      return PracticeLabDestination.voicePractice;
    case SkillType.writing:
      return PracticeLabDestination.lexi;
  }
}

List<PracticeLabItem> buildPracticeLabItems({
  List<SkillScore> weakestSkills = const [],
}) {
  final weakSkillSet = weakestSkills.map((score) => score.skill).toSet();

  return _basePracticeLabItems
      .map(
        (item) => item.copyWith(recommended: weakSkillSet.contains(item.skill)),
      )
      .toList(growable: false);
}

List<PracticeLabItem> recommendedPracticeItems({
  required List<PracticeLabItem> items,
  int limit = 2,
  bool hasPremium = false,
}) {
  bool usable(PracticeLabItem item) => hasPremium || !item.premiumOnly;

  // One card per skill. Two cards share a skill (reading is both the news
  // card and the mistake notebook), so an unfiltered take(2) could hand back
  // two ways to do the same thing and hide the learner's second weakness.
  final seenSkills = <SkillType>{};
  final picked = <PracticeLabItem>[];

  void add(Iterable<PracticeLabItem> candidates) {
    for (final item in candidates) {
      if (picked.length >= limit) return;
      if (!usable(item)) continue;
      if (!seenSkills.add(item.skill)) continue;
      picked.add(item);
    }
  }

  // Recommending a locked card is worse than recommending nothing: writing is
  // premium and is almost always among the weakest skills, so the very first
  // suggestion a free learner saw was a padlock.
  add(items.where((item) => item.recommended));
  add(items);

  return List.unmodifiable(picked);
}

const List<PracticeLabItem> _basePracticeLabItems = [
  PracticeLabItem(
    skill: SkillType.vocabulary,
    titleKey: 'practiceLab.skills.vocabulary.title',
    subtitleKey: 'practiceLab.skills.vocabulary.subtitle',
    actionKey: 'practiceLab.skills.vocabulary.action',
    estimateKey: 'practiceLab.skills.vocabulary.estimate',
    icon: Icons.style_rounded,
    color: AppColors.orange,
    destination: PracticeLabDestination.vocabularyReview,
  ),
  PracticeLabItem(
    skill: SkillType.speaking,
    titleKey: 'practiceLab.skills.speaking.title',
    subtitleKey: 'practiceLab.skills.speaking.subtitle',
    actionKey: 'practiceLab.skills.speaking.action',
    estimateKey: 'practiceLab.skills.speaking.estimate',
    icon: Icons.mic_rounded,
    color: AppColors.greenSuccessBright,
    destination: PracticeLabDestination.voicePractice,
  ),
  PracticeLabItem(
    skill: SkillType.listening,
    titleKey: 'practiceLab.skills.listening.title',
    subtitleKey: 'practiceLab.skills.listening.subtitle',
    actionKey: 'practiceLab.skills.listening.action',
    estimateKey: 'practiceLab.skills.listening.estimate',
    icon: Icons.headphones_rounded,
    color: AppColors.teal,
    destination: PracticeLabDestination.podcast,
  ),
  PracticeLabItem(
    skill: SkillType.reading,
    titleKey: 'practiceLab.skills.reading.title',
    subtitleKey: 'practiceLab.skills.reading.subtitle',
    actionKey: 'practiceLab.skills.reading.action',
    estimateKey: 'practiceLab.skills.reading.estimate',
    icon: Icons.menu_book_rounded,
    color: AppColors.primary,
    destination: PracticeLabDestination.news,
  ),
  PracticeLabItem(
    skill: SkillType.grammar,
    titleKey: 'practiceLab.skills.grammar.title',
    subtitleKey: 'practiceLab.skills.grammar.subtitle',
    actionKey: 'practiceLab.skills.grammar.action',
    estimateKey: 'practiceLab.skills.grammar.estimate',
    icon: Icons.edit_note_rounded,
    color: AppColors.purple,
    destination: PracticeLabDestination.games,
  ),
  PracticeLabItem(
    skill: SkillType.reading,
    titleKey: 'practiceLab.skills.mistakes.title',
    subtitleKey: 'practiceLab.skills.mistakes.subtitle',
    actionKey: 'practiceLab.skills.mistakes.action',
    estimateKey: 'practiceLab.skills.mistakes.estimate',
    icon: Icons.rule_folder_rounded,
    color: AppColors.errorBright,
    destination: PracticeLabDestination.mistakeNotebook,
  ),
  PracticeLabItem(
    skill: SkillType.writing,
    titleKey: 'practiceLab.skills.writing.title',
    subtitleKey: 'practiceLab.skills.writing.subtitle',
    actionKey: 'practiceLab.skills.writing.action',
    estimateKey: 'practiceLab.skills.writing.estimate',
    icon: Icons.drive_file_rename_outline_rounded,
    color: AppColors.deepOrange,
    destination: PracticeLabDestination.lexi,
    premiumOnly: true,
  ),
];
