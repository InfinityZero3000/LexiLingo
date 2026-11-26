import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// On the web each tab reads its own cached copy of the shared localStorage.
/// A file that stores lists or JSON usually reads, changes and writes back, so
/// it must say which side it is on: `freshPreferences()`, or a reason below.
const _allowed = {
  // Caches of server data: a stale write is replaced by the next fetch.
  'core/services/encrypted_local_cache_service.dart': 'cache',
  'features/course/data/datasources/course_local_datasource.dart': 'cache',
  'features/user/data/datasources/user_local_data_source_web.dart': 'cache',
  'features/user/data/datasources/settings_local_data_source_web.dart': 'cache',
  'features/user/data/datasources/streak_local_data_source_web.dart': 'cache',
  'features/user/data/datasources/daily_goal_local_data_source_web.dart':
      'cache',
  // Convenience state whose loss costs nothing the learner made.
  'features/home/presentation/providers/promo_banner_provider.dart':
      'dismissed banners',
  'features/chat/presentation/providers/story_provider.dart': 'recent topics',
  'features/chat/data/datasources/chat_local_datasource_web.dart':
      'local chat copy',
  'features/auth/presentation/widgets/auth_wrapper.dart':
      'one-time onboarding answers',
  // Runs once at sign-in, moving legacy keys.
  'core/services/user_scope_service.dart': 'one-time migration',
};

Iterable<File> _dartFiles() => Directory('lib')
    .listSync(recursive: true)
    .whereType<File>()
    .where((f) => f.path.endsWith('.dart'));

void main() {
  test('stored collections are rewritten from fresh preferences', () {
    final writes = RegExp(r'\.(setString|setStringList)\(');
    final collection = RegExp(r'jsonDecode|json\.decode|getStringList');
    final unsafe = <String>[
      for (final file in _dartFiles())
        if (!file.path.startsWith('lib/features/admin/'))
          if (file.readAsStringSync() case final source
              when writes.hasMatch(source) &&
                  collection.hasMatch(source) &&
                  !source.contains('freshPreferences') &&
                  !_allowed.containsKey(file.path.substring(4)))
            file.path,
    ];

    expect(
      unsafe,
      isEmpty,
      reason:
          'read with freshPreferences() before writing back, or add the file '
          'to _allowed with the reason a lost write is harmless',
    );
  });

  test('only refreshBackendToken spends a refresh token', () {
    // Refresh tokens are single-use: a second caller that skips its lock and
    // reload gets the whole session revoked.
    final callers = [
      for (final file in _dartFiles())
        if (file.readAsStringSync().contains(
          RegExp(r"""/auth/refresh(-token)?['"]"""),
        ))
          file.path,
    ];

    expect(callers, ['lib/core/di/core_di.dart']);
  });
}
