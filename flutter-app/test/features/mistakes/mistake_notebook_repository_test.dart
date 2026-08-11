import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_remote_datasource.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('MistakeNotebookRepository', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('saves entries sorted by review state and recency', () async {
      final repository = MistakeNotebookRepository();
      final older = _entry(id: 'older', createdAt: DateTime(2026));
      final newer = _entry(id: 'newer', createdAt: DateTime(2026, 1, 2));

      await repository.saveMistake(older);
      await repository.saveMistake(newer);

      final entries = await repository.getEntries();

      expect(entries.map((entry) => entry.id), ['newer', 'older']);
    });

    test('upserts repeated mistake and makes it unreviewed again', () async {
      final repository = MistakeNotebookRepository();
      final mistake = _entry(id: 'repeat', createdAt: DateTime(2026));

      await repository.saveMistake(mistake);
      await repository.markReviewed('repeat');
      await repository.saveMistake(
        mistake.copyWith(selectedAnswer: 'C', createdAt: DateTime(2026, 1, 3)),
      );

      final entries = await repository.getEntries();

      expect(entries, hasLength(1));
      expect(entries.single.selectedAnswer, 'C');
      expect(entries.single.isReviewed, isFalse);
      expect(entries.single.reviewCount, 1);
    });

    test('marks entries reviewed and clears reviewed items', () async {
      final repository = MistakeNotebookRepository();

      await repository.saveMistake(_entry(id: 'a'));
      await repository.saveMistake(_entry(id: 'b'));
      await repository.markReviewed('a');

      var entries = await repository.getEntries();
      expect(entries.first.id, 'b');
      expect(entries.last.id, 'a');
      expect(entries.last.reviewCount, 1);

      await repository.clearReviewed();
      entries = await repository.getEntries();

      expect(entries.map((entry) => entry.id), ['b']);
    });

    test('buildId is stable for identical quiz context', () {
      final first = MistakeNotebookEntry.buildId(
        sourceType: 'book_quiz',
        sourceId: 'book-1',
        questionId: 'q1',
        selectedAnswer: 'A',
      );
      final second = MistakeNotebookEntry.buildId(
        sourceType: 'book_quiz',
        sourceId: 'book-1',
        questionId: 'q1',
        selectedAnswer: 'A',
      );

      expect(first, second);
    });

    test('syncs saved mistakes to remote datasource when available', () async {
      final remote = _FakeMistakeRemoteDataSource();
      final repository = MistakeNotebookRepository(remoteDataSource: remote);
      final mistake = _entry(id: 'remote-save');

      await repository.saveMistake(mistake);

      expect(remote.saved.map((entry) => entry.id), ['remote-save']);
      final entries = await repository.getEntries();
      expect(entries.map((entry) => entry.id), ['remote-save']);
    });

    test('queues failed remote saves and retries on next load', () async {
      final remote = _FakeMistakeRemoteDataSource(shouldFail: true);
      final repository = MistakeNotebookRepository(remoteDataSource: remote);
      final mistake = _entry(id: 'queued');

      await repository.saveMistake(mistake);

      expect(remote.saved, isEmpty);
      remote.shouldFail = false;

      final entries = await repository.getEntries();

      expect(entries.map((entry) => entry.id), ['queued']);
      expect(remote.saved.map((entry) => entry.id), ['queued']);
      expect(remote.saveCalls, 2);
    });

    test(
      'does not flush queued user A operations while user B is active',
      () async {
        final remote = _FakeMistakeRemoteDataSource(shouldFail: true);
        final repository = MistakeNotebookRepository(remoteDataSource: remote);

        await UserScopeService.setActiveUserId('user-a');
        await repository.saveMistake(_entry(id: 'queued-user-a'));
        expect(remote.saveCalls, 1);

        remote.shouldFail = false;
        await UserScopeService.setActiveUserId('user-b');
        await repository.getEntries();
        expect(remote.saveCalls, 1);
        expect(remote.saved, isEmpty);

        await UserScopeService.setActiveUserId('user-a');
        await repository.getEntries();
        expect(remote.saveCalls, 2);
        expect(remote.saved.map((entry) => entry.id), ['queued-user-a']);
      },
    );

    test('suppresses remote entries while delete is still pending', () async {
      final remote = _FakeMistakeRemoteDataSource();
      remote.saved.add(_entry(id: 'delete-pending'));
      final repository = MistakeNotebookRepository(remoteDataSource: remote);

      await repository.getEntries();
      remote.failDeletes = true;
      await repository.delete('delete-pending');

      final entries = await repository.getEntries();

      expect(entries, isEmpty);
      expect(remote.saved.map((entry) => entry.id), ['delete-pending']);
    });

    test('syncs review and delete operations to remote datasource', () async {
      final remote = _FakeMistakeRemoteDataSource();
      final repository = MistakeNotebookRepository(remoteDataSource: remote);

      await repository.saveMistake(_entry(id: 'review-delete'));
      await repository.markReviewed('review-delete');
      await repository.delete('review-delete');

      expect(remote.reviewedIds, ['review-delete']);
      expect(remote.deletedIds, ['review-delete']);
    });

    test('scopes local entries by active user', () async {
      final repository = MistakeNotebookRepository();

      await UserScopeService.setActiveUserId('user-a');
      await repository.saveMistake(_entry(id: 'user-a-entry'));

      await UserScopeService.setActiveUserId('user-b');
      expect(await repository.getEntries(), isEmpty);

      await repository.saveMistake(_entry(id: 'user-b-entry'));
      expect((await repository.getEntries()).map((entry) => entry.id), [
        'user-b-entry',
      ]);

      await UserScopeService.setActiveUserId('user-a');
      expect((await repository.getEntries()).map((entry) => entry.id), [
        'user-a-entry',
      ]);
    });
  });
}

MistakeNotebookEntry _entry({required String id, DateTime? createdAt}) {
  return MistakeNotebookEntry(
    id: id,
    sourceType: 'book_quiz',
    sourceId: 'book-1',
    sourceTitle: 'Demo book',
    question: 'What happened?',
    selectedAnswer: 'A',
    correctAnswer: 'B',
    explanation: 'Because the text says so.',
    skill: 'reading',
    createdAt: createdAt ?? DateTime(2026),
  );
}

class _FakeMistakeRemoteDataSource implements MistakeNotebookRemoteDataSource {
  final saved = <MistakeNotebookEntry>[];
  final reviewedIds = <String>[];
  final deletedIds = <String>[];
  bool shouldFail;
  bool failDeletes = false;
  int saveCalls = 0;

  _FakeMistakeRemoteDataSource({this.shouldFail = false});

  @override
  Future<List<MistakeNotebookEntry>> getEntries({String status = 'all'}) async {
    if (shouldFail) throw Exception('offline');
    return saved;
  }

  @override
  Future<MistakeNotebookEntry> saveMistake(MistakeNotebookEntry entry) async {
    saveCalls++;
    if (shouldFail) throw Exception('offline');
    saved.removeWhere((item) => item.id == entry.id);
    saved.add(entry);
    return entry;
  }

  @override
  Future<MistakeNotebookEntry> markReviewed(String id) async {
    if (shouldFail) throw Exception('offline');
    reviewedIds.add(id);
    return saved.firstWhere((entry) => entry.id == id);
  }

  @override
  Future<MistakeNotebookEntry> reopen(String id) async {
    if (shouldFail) throw Exception('offline');
    return saved.firstWhere((entry) => entry.id == id);
  }

  @override
  Future<void> delete(String id) async {
    if (shouldFail || failDeletes) throw Exception('offline');
    deletedIds.add(id);
    saved.removeWhere((entry) => entry.id == id);
  }
}
