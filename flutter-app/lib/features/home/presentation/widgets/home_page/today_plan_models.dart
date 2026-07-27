import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/course/domain/entities/course_entity.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';

enum TodayPlanDestination {
  vocabularyReview,
  courseList,
  games,
  lexi,
  voice,
  news,
  podcast,
}

enum TodayPlanTaskType { vocabulary, course, skill, challenge, conversation }

class TodayPlanTask {
  const TodayPlanTask({
    required this.type,
    required this.destination,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.progress,
    this.isCompleted = false,
    this.metaLabel,
    this.rewardLabel,
  });

  final TodayPlanTaskType type;
  final TodayPlanDestination destination;
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final double progress;
  final bool isCompleted;
  final String? metaLabel;
  final String? rewardLabel;
}

class TodayPlanSnapshot {
  const TodayPlanSnapshot(this.tasks);

  final List<TodayPlanTask> tasks;

  int get completedCount => tasks.where((task) => task.isCompleted).length;
  int get totalCount => tasks.length;
  double get progress => totalCount == 0 ? 0 : completedCount / totalCount;

  TodayPlanTask? get nextTask {
    for (final task in tasks) {
      if (!task.isCompleted) return task;
    }
    return tasks.isEmpty ? null : tasks.first;
  }
}

TodayPlanSnapshot buildTodayPlanSnapshot({
  required List<CourseEntity> enrolledCourses,
  required List<DailyChallengeEntity> challenges,
  required List<SkillScore> weakestSkills,
  int? dueVocabularyCount,
}) {
  final tasks = <TodayPlanTask>[];

  tasks.add(_buildVocabularyTask(dueVocabularyCount));
  tasks.add(_buildCourseTask(enrolledCourses));
  tasks.add(_buildSkillTask(weakestSkills));
  tasks.add(_buildChallengeTask(challenges));
  tasks.add(_buildConversationTask());

  return TodayPlanSnapshot(tasks);
}

TodayPlanTask _buildVocabularyTask(int? dueCount) {
  final count = dueCount ?? 0;
  final hasDueWords = dueCount == null || count > 0;

  return TodayPlanTask(
    type: TodayPlanTaskType.vocabulary,
    destination: TodayPlanDestination.vocabularyReview,
    icon: Icons.style_rounded,
    color: const Color(0xFFE85D9E),
    title: 'home.todayPlan.vocabularyTitle'.tr(),
    subtitle: dueCount == null
        ? 'home.todayPlan.vocabularyCheckSubtitle'.tr()
        : count > 0
        ? 'home.todayPlan.vocabularyDueSubtitle'.tr(
            namedArgs: {'count': '$count'},
          )
        : 'home.todayPlan.vocabularyDoneSubtitle'.tr(),
    actionLabel: hasDueWords
        ? 'home.todayPlan.reviewAction'.tr()
        : 'home.todayPlan.checkAction'.tr(),
    metaLabel: 'home.todayPlan.vocabularyMeta'.tr(),
    progress: hasDueWords ? 0 : 1,
    isCompleted: !hasDueWords,
  );
}

TodayPlanTask _buildCourseTask(List<CourseEntity> enrolledCourses) {
  final course = enrolledCourses
      .where((item) => (item.userProgress ?? 0) < 1)
      .cast<CourseEntity?>()
      .firstWhere((item) => item != null, orElse: () => null);

  if (course == null) {
    return TodayPlanTask(
      type: TodayPlanTaskType.course,
      destination: TodayPlanDestination.courseList,
      icon: Icons.menu_book_rounded,
      color: const Color(0xFF2687D9),
      title: 'home.todayPlan.courseFallbackTitle'.tr(),
      subtitle: 'home.todayPlan.courseFallbackSubtitle'.tr(),
      actionLabel: 'home.todayPlan.browseAction'.tr(),
      metaLabel: 'home.todayPlan.courseMeta'.tr(),
      progress: 0,
    );
  }

  final progress = (course.userProgress ?? 0).clamp(0.0, 1.0);

  return TodayPlanTask(
    type: TodayPlanTaskType.course,
    destination: TodayPlanDestination.courseList,
    icon: Icons.menu_book_rounded,
    color: const Color(0xFF2687D9),
    title: course.title,
    subtitle: 'home.todayPlan.courseSubtitle'.tr(
      namedArgs: {'level': course.level},
    ),
    actionLabel: 'home.todayPlan.continueAction'.tr(),
    metaLabel: 'home.todayPlan.courseProgress'.tr(
      namedArgs: {'percent': '${(progress * 100).round()}'},
    ),
    rewardLabel: course.totalXp > 0 ? '+${course.totalXp} XP' : null,
    progress: progress,
    isCompleted: progress >= 1,
  );
}

TodayPlanTask _buildSkillTask(List<SkillScore> weakestSkills) {
  final skill = weakestSkills.isEmpty ? null : weakestSkills.first;

  if (skill == null) {
    return TodayPlanTask(
      type: TodayPlanTaskType.skill,
      destination: TodayPlanDestination.voice,
      icon: Icons.mic_rounded,
      color: const Color(0xFF18A999),
      title: 'home.todayPlan.skillFallbackTitle'.tr(),
      subtitle: 'home.todayPlan.skillFallbackSubtitle'.tr(),
      actionLabel: 'home.todayPlan.practiceAction'.tr(),
      metaLabel: 'home.todayPlan.skillMeta'.tr(),
      progress: 0,
    );
  }

  final destination = _destinationForSkill(skill.skill);

  return TodayPlanTask(
    type: TodayPlanTaskType.skill,
    destination: destination,
    icon: skill.skill.icon,
    color: const Color(0xFF18A999),
    title: 'home.todayPlan.skillTitle'.tr(
      namedArgs: {'skill': skill.skill.displayName},
    ),
    subtitle: 'home.todayPlan.skillSubtitle'.tr(
      namedArgs: {'level': skill.estimatedLevel},
    ),
    actionLabel: 'home.todayPlan.practiceAction'.tr(),
    metaLabel: 'home.todayPlan.skillScore'.tr(
      namedArgs: {'score': '${skill.score.round()}'},
    ),
    progress: (skill.score / 100).clamp(0.0, 1.0),
    isCompleted: skill.score >= 80,
  );
}

TodayPlanDestination _destinationForSkill(SkillType skill) {
  switch (skill) {
    case SkillType.vocabulary:
      return TodayPlanDestination.vocabularyReview;
    case SkillType.grammar:
    case SkillType.writing:
      return TodayPlanDestination.games;
    case SkillType.reading:
      return TodayPlanDestination.news;
    case SkillType.listening:
      return TodayPlanDestination.podcast;
    case SkillType.speaking:
      return TodayPlanDestination.voice;
  }
}

TodayPlanTask _buildChallengeTask(List<DailyChallengeEntity> challenges) {
  DailyChallengeEntity? challenge;
  for (final item in challenges) {
    if (!item.isCompleted) {
      challenge = item;
      break;
    }
  }
  challenge ??= challenges.isEmpty ? null : challenges.first;

  if (challenge == null) {
    return TodayPlanTask(
      type: TodayPlanTaskType.challenge,
      destination: TodayPlanDestination.games,
      icon: Icons.emoji_events_rounded,
      color: const Color(0xFFFFA319),
      title: 'home.todayPlan.challengeFallbackTitle'.tr(),
      subtitle: 'home.todayPlan.challengeFallbackSubtitle'.tr(),
      actionLabel: 'home.todayPlan.playAction'.tr(),
      metaLabel: 'home.todayPlan.challengeMeta'.tr(),
      progress: 0,
    );
  }

  return TodayPlanTask(
    type: TodayPlanTaskType.challenge,
    destination: _destinationForChallenge(challenge),
    icon: Icons.emoji_events_rounded,
    color: const Color(0xFFFFA319),
    title: challenge.title,
    subtitle: challenge.description,
    actionLabel: challenge.isCompleted
        ? 'home.todayPlan.doneAction'.tr()
        : 'home.todayPlan.startAction'.tr(),
    metaLabel: 'home.todayPlan.challengeProgress'.tr(
      namedArgs: {
        'current': '${challenge.current}',
        'target': '${challenge.target}',
      },
    ),
    rewardLabel: '+${challenge.xpReward} XP',
    progress: challenge.progress,
    isCompleted: challenge.isCompleted,
  );
}

TodayPlanDestination _destinationForChallenge(DailyChallengeEntity challenge) {
  switch (challenge.category) {
    case 'vocabulary':
      return TodayPlanDestination.vocabularyReview;
    case 'voice':
      return TodayPlanDestination.voice;
    default:
      return TodayPlanDestination.games;
  }
}

TodayPlanTask _buildConversationTask() {
  return TodayPlanTask(
    type: TodayPlanTaskType.conversation,
    destination: TodayPlanDestination.lexi,
    icon: Icons.auto_awesome_rounded,
    color: const Color(0xFF7C5CFF),
    title: 'home.todayPlan.lexiTitle'.tr(),
    subtitle: 'home.todayPlan.lexiSubtitle'.tr(),
    actionLabel: 'home.todayPlan.chatAction'.tr(),
    metaLabel: 'home.todayPlan.lexiMeta'.tr(),
    progress: 0,
  );
}
