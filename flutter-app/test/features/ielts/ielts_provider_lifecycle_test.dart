import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/ielts/data/datasources/ielts_data_source.dart';
import 'package:lexilingo_app/features/ielts/domain/entities/ielts_entities.dart';
import 'package:lexilingo_app/features/ielts/presentation/providers/ielts_provider.dart';

class _Source extends IeltsDataSource {
  _Source() : super(apiClient: ApiClient());

  final startGate = Completer<void>();
  bool failSubmit = false;
  final saved = <Map<String, dynamic>>[];
  int submits = 0;

  @override
  Future<IeltsAttemptState> startAttempt(
    String testId, {
    String skillScope = 'full',
  }) async {
    await startGate.future;
    return const IeltsAttemptState(
      attemptId: 'a1',
      status: 'in_progress',
      skillScope: 'full',
      paper: IeltsPaper(),
    );
  }

  @override
  Future<void> saveAnswers(
    String attemptId,
    Map<String, dynamic> answers, {
    int timeSpentSeconds = 0,
  }) async {
    saved.add(Map.of(answers));
  }

  @override
  Future<Map<String, dynamic>> submit(
    String attemptId,
    Map<String, dynamic> answers, {
    int timeSpentSeconds = 0,
  }) async {
    submits++;
    if (failSubmit) throw Exception('boom');
    return {};
  }
}

void main() {
  test('leaving while a sitting is loading does not notify a disposed provider',
      () async {
    final source = _Source();
    final provider = IeltsProvider(dataSource: source);

    final start = provider.startTest('t1');
    provider.dispose();
    source.startGate.complete();

    expect(await start, isTrue);
  });

  test('answers typed since the last autosave are flushed on dispose', () async {
    final source = _Source()..startGate.complete();
    final provider = IeltsProvider(dataSource: source);
    await provider.startTest('t1');

    provider.setAnswer('q1', 'B');
    provider.dispose();
    await Future<void>.delayed(Duration.zero);

    expect(source.saved, [
      {'q1': 'B'},
    ]);
  });

  test('a second submit while one is running is ignored', () async {
    final source = _Source()..startGate.complete();
    source.failSubmit = true;
    final provider = IeltsProvider(dataSource: source);
    await provider.startTest('t1');

    final a = provider.submit();
    final b = provider.submit();
    await Future.wait([a, b]);

    expect(source.submits, 1);
    provider.dispose();
  });
}
