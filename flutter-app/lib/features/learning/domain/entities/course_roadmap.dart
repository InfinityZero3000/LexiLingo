class LessonProgress {
  final String lessonId;
  final int lessonNumber;
  final String title;
  final String? description;
  final bool isLocked;
  final bool isCurrent;
  final bool isCompleted;
  final double? bestScore;
  final int starsEarned;
  final int attemptsCount;
  final double completionPercentage;
  final String? iconUrl;
  final String backgroundColor;

  const LessonProgress({
    required this.lessonId,
    required this.lessonNumber,
    required this.title,
    this.description,
    required this.isLocked,
    required this.isCurrent,
    required this.isCompleted,
    this.bestScore,
    required this.starsEarned,
    required this.attemptsCount,
    required this.completionPercentage,
    this.iconUrl,
    required this.backgroundColor,
  });
}

class UnitRoadmap {
  final String unitId;
  final int unitNumber;
  final String title;
  final String? description;
  final int totalLessons;
  final int completedLessons;
  final double completionPercentage;
  final bool isCurrent;
  final List<LessonProgress> lessons;
  final String? iconUrl;
  final String backgroundColor;

  const UnitRoadmap({
    required this.unitId,
    required this.unitNumber,
    required this.title,
    this.description,
    required this.totalLessons,
    required this.completedLessons,
    required this.completionPercentage,
    required this.isCurrent,
    required this.lessons,
    this.iconUrl,
    required this.backgroundColor,
  });
}

class CourseRoadmap {
  final String courseId;
  final String courseTitle;
  final String level;
  final int totalUnits;
  final int completedUnits;
  final int totalLessons;
  final int completedLessons;
  final double completionPercentage;
  final int totalXpEarned;
  final int currentStreak;
  final List<UnitRoadmap> units;

  const CourseRoadmap({
    required this.courseId,
    required this.courseTitle,
    required this.level,
    required this.totalUnits,
    required this.completedUnits,
    required this.totalLessons,
    required this.completedLessons,
    required this.completionPercentage,
    required this.totalXpEarned,
    required this.currentStreak,
    required this.units,
  });
}
