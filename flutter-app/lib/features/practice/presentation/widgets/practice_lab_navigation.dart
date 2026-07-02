import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/practice/presentation/widgets/practice_lab_models.dart';
import 'package:lexilingo_app/features/voice/presentation/screens/voice_practice_screen.dart';

void openPracticeLabItem(BuildContext context, PracticeLabItem item) {
  switch (item.destination) {
    case PracticeLabDestination.vocabularyReview:
      Navigator.of(context).pushNamed('/vocabulary/review');
      break;
    case PracticeLabDestination.voicePractice:
      Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => const VoicePracticeScreen()));
      break;
    case PracticeLabDestination.podcast:
      Navigator.of(context).pushNamed('/podcast');
      break;
    case PracticeLabDestination.news:
      Navigator.of(context).pushNamed('/news');
      break;
    case PracticeLabDestination.games:
      Navigator.of(context).pushNamed('/games');
      break;
    case PracticeLabDestination.lexi:
      Navigator.of(context).pushNamed('/lexi');
      break;
    case PracticeLabDestination.mistakeNotebook:
      Navigator.of(context).pushNamed('/mistake-notebook');
      break;
  }
}
