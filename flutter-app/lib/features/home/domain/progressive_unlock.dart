/// Brand-new learners see the start button and Vocabulary; the rest of Home
/// opens after their first completed lesson.
bool secondaryFeaturesLocked({
  required bool flagEnabled,
  required int? lessonsCompleted,
}) => flagEnabled && lessonsCompleted == 0;
