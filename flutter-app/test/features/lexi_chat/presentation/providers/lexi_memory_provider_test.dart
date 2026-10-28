import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_memory_provider.dart';

class _MemoryRepo implements LexiChatRepository {
  Map<String, String> stored = {};
  Object? error;
  final forgotten = <String>[];
  int forgetAllCalls = 0;

  @override
  Future<Map<String, String>> getMemory() async {
    if (error != null) throw error!;
    return stored;
  }

  @override
  Future<void> forgetMemory() async {
    if (error != null) throw error!;
    forgetAllCalls += 1;
  }

  @override
  Future<void> forgetMemoryFact(String key) async {
    if (error != null) throw error!;
    forgotten.add(key);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName}');
}

void main() {
  test('load shows facts in a fixed order, unknown keys hidden', () async {
    final repo = _MemoryRepo()
      ..stored = {
        'interests': 'football',
        'secret': 'x',
        'preferred_name': 'Thang',
      };
    final provider = LexiMemoryProvider(repository: repo);

    expect(provider.status, LexiMemoryStatus.loading);
    await provider.load();

    expect(provider.status, LexiMemoryStatus.ready);
    expect(provider.facts.map((e) => e.key), ['preferred_name', 'interests']);
  });

  test('a failed load is reported, not shown as an empty memory', () async {
    final repo = _MemoryRepo()..error = Exception('offline');
    final provider = LexiMemoryProvider(repository: repo);

    await provider.load();

    expect(provider.status, LexiMemoryStatus.failed);
    expect(provider.facts, isEmpty);
  });

  test('forget removes the row only after the server confirmed', () async {
    final repo = _MemoryRepo()..stored = {'goal': 'IELTS', 'interests': 'golf'};
    final provider = LexiMemoryProvider(repository: repo);
    await provider.load();

    repo.error = Exception('500');
    expect(await provider.forget('goal'), isFalse);
    expect(provider.facts.map((e) => e.key), ['goal', 'interests']);

    repo.error = null;
    expect(await provider.forget('goal'), isTrue);
    expect(repo.forgotten, ['goal']);
    expect(provider.facts.map((e) => e.key), ['interests']);
  });

  test('forgetAll clears the list, and keeps it when the call fails', () async {
    final repo = _MemoryRepo()..stored = {'goal': 'IELTS'};
    final provider = LexiMemoryProvider(repository: repo);
    await provider.load();

    repo.error = Exception('500');
    expect(await provider.forgetAll(), isFalse);
    expect(provider.facts, hasLength(1));

    repo.error = null;
    expect(await provider.forgetAll(), isTrue);
    expect(repo.forgetAllCalls, 1);
    expect(provider.facts, isEmpty);
    expect(provider.status, LexiMemoryStatus.ready);
  });

  test('a response that lands after dispose does not notify', () async {
    final repo = _MemoryRepo()..stored = {'goal': 'IELTS'};
    final provider = LexiMemoryProvider(repository: repo);
    final pending = provider.load();
    provider.dispose();
    await pending; // would throw "used after dispose" without the guard
  });
}
