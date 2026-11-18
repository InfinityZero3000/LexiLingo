import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';
import 'package:lexilingo_app/features/level/presentation/providers/placement_test_provider.dart';

class _Source extends ProficiencyDataSource {
  _Source() : super(apiClient: ApiClient(enableLogging: false));

  final gate = Completer<Map<String, dynamic>>();
  int submits = 0;

  @override
  Future<Map<String, dynamic>> submitPlacementTest({
    required Map<String, int> answers,
    required int timeTakenSeconds,
  }) {
    submits++;
    return gate.future;
  }
}

void main() {
  test('a second submit while one is in flight is ignored', () async {
    final source = _Source();
    final provider = PlacementTestProvider(dataSource: source);

    final first = provider.submitTest({'1': 0}, 10);
    final second = await provider.submitTest({'1': 0}, 10);
    source.gate.complete({'level': 'A2'});

    expect(second, isFalse);
    expect(await first, isTrue);
    expect(source.submits, 1);
  });
}
