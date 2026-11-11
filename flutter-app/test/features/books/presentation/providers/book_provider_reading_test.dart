import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';

class _Repo extends BookRepository {
  _Repo({this.entries = const [], this.fail = false});

  final List<ReadingEntry> entries;
  final bool fail;
  final snapshots = <String>[];
  final savedProgress = <UserBook>[];

  @override
  Future<List<ReadingEntry>> getContinueReading({int limit = 5}) async {
    if (fail) throw Exception('prefs unavailable');
    return entries;
  }

  @override
  Future<void> saveReadingSnapshot(Book book) async => snapshots.add(book.id);

  @override
  Future<void> saveProgress(UserBook progress) async =>
      savedProgress.add(progress);

  @override
  Future<UserBook?> getProgress(String bookId) async => null;

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;

  @override
  Future<String> fetchBookText(Book book) async => 'A' * 6000;

  @override
  Future<void> awardXP({
    required int baseXp,
    required String sourceId,
    String sourceDetail = 'book_reading',
  }) async {}
}

const _book = Book(id: 'b1', title: 'T');

void main() {
  test(
    'loadContinueReading exposes the repository list and notifies',
    () async {
      final entry = ReadingEntry(
        book: _book,
        progress: const UserBook(bookId: 'b1', readingProgress: 0.4),
      );
      final provider = BookProvider(repository: _Repo(entries: [entry]));
      var notified = 0;
      provider.addListener(() => notified++);

      await provider.loadContinueReading();

      expect(provider.continueReading.single.book.id, 'b1');
      expect(notified, 1);
    },
  );

  test('a failing read leaves the shelf empty instead of throwing', () async {
    final provider = BookProvider(repository: _Repo(fail: true));
    await provider.loadContinueReading();
    expect(provider.continueReading, isEmpty);
  });

  test('turning pages snapshots the book once, not on every page', () async {
    final repo = _Repo();
    final provider = BookProvider(repository: repo);
    await provider.openBook(_book);
    await provider.loadBookText(charsPerPage: 1000);
    expect(provider.totalPages, greaterThan(2));

    await provider.nextPage();
    await provider.nextPage();
    await provider.previousPage();

    expect(
      repo.savedProgress,
      hasLength(3),
      reason: 'progress saved each turn',
    );
    expect(repo.snapshots, ['b1'], reason: 'snapshot written exactly once');
  });
}
