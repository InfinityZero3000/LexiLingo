import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import 'package:lexilingo_app/features/auth/presentation/providers/auth_provider.dart';
import 'package:lexilingo_app/features/home/presentation/providers/home_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/level_provider.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_chat_provider.dart';

/// The one place the app catches up after a CEFR level change — a self-set
/// level, a placement or a level exam. The backend has already refreshed its
/// own caches and ai-service's; this refreshes what the app holds.
abstract final class LevelSync {
  static Future<void> afterLevelChange(BuildContext context) async {
    final auth = _maybe<AuthProvider>(context);
    final proficiency = _maybe<ProficiencyProvider>(context);
    final level = _maybe<LevelProvider>(context);
    final home = _maybe<HomeProvider>(context);
    final lexi = _maybe<LexiChatProvider>(context);

    await Future.wait([
      if (auth != null) auth.refreshCurrentUser(),
      if (proficiency != null) proficiency.refreshAfterLevelChange(),
      if (level != null) level.fetchLevelFull(),
    ]);
    final current = auth?.currentUser?.cefrLevel;
    if (current != null) lexi?.setLearnerLevel(current);
    home?.refreshData();
  }

  static T? _maybe<T>(BuildContext context) {
    try {
      return Provider.of<T>(context, listen: false);
    } on ProviderNotFoundException {
      return null;
    }
  }
}
