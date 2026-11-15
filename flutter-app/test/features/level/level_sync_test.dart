import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/level_sync.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:provider/provider.dart';

class _Source extends ProficiencyDataSource {
  _Source() : super(apiClient: ApiClient(enableLogging: false));

  final calls = <String>[];

  @override
  Future<void> invalidateProfile() async => calls.add('invalidate');

  @override
  Future<ProficiencyProfile> getProfile() async {
    calls.add('profile');
    return ProficiencyProfile.fromJson({
      'assessed_level': 'B2',
      'certified_level': 'B1',
      'level_verified': false,
    });
  }

  @override
  Future<Map<String, dynamic>> getLevelHistory({int limit = 10}) async {
    calls.add('history');
    return {'history': []};
  }
}

void main() {
  testWidgets('drops the cached profile before reloading it and the history', (
    tester,
  ) async {
    final source = _Source();
    final proficiency = ProficiencyProvider(dataSource: source);
    late BuildContext captured;

    await tester.pumpWidget(
      ChangeNotifierProvider<ProficiencyProvider>.value(
        value: proficiency,
        child: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox();
          },
        ),
      ),
    );

    await LevelSync.afterLevelChange(captured);

    // The cache goes first, or the reload would be served the old level.
    expect(source.calls.first, 'invalidate');
    expect(source.calls, containsAll(['profile', 'history']));
    expect(proficiency.assessedLevel, 'B2');
    expect(proficiency.certifiedLevel, 'B1');
    expect(proficiency.levelVerified, isFalse);
  });

  testWidgets('does not need every provider to be present', (tester) async {
    late BuildContext captured;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    );

    await expectLater(LevelSync.afterLevelChange(captured), completes);
  });
}
