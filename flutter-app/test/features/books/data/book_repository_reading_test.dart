import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:shared_preferences/shared_preferences.dart';

Book _book(String id) => Book(
  id: id,
  title: 'Title $id',
  author: 'Author $id',
  coverUrl: 'https://x/$id.jpg',
  cefrLevel: 'B2',
  topic: 'Fantasy',
  chapterCount: 12,
  wordCount: 80000,
);

UserBook _progress(
  String id, {
  int page = 10,
  int total = 100,
  int minute = 0,
  bool read = true,
}) => UserBook(
  bookId: id,
  currentPage: page,
  totalPages: total,
  readingProgress: total == 0 ? 0 : page / total,
  lastReadAt: read ? DateTime(2026, 10, 23, 9, minute) : null,
);

void main() {
  late BookRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = BookRepository();
  });

  group('Book.toJson', () {
    test('round-trips every field the library shows', () {
      final back = Book.fromJson(_book('a').toJson());
      expect(back.id, 'a');
      expect(back.title, 'Title a');
      expect(back.author, 'Author a');
      expect(back.coverUrl, 'https://x/a.jpg');
      expect(back.cefrLevel, 'B2');
      expect(back.topic, 'Fantasy');
      expect(back.chapterCount, 12);
      expect(back.wordCount, 80000);
    });

    test(
      'saveBook still restores the same book (it now uses toJson)',
      () async {
        await repo.saveBook(_book('a'));
        final saved = await repo.getSavedBooks();
        expect(saved.single.title, 'Title a');
        expect(saved.single.coverUrl, 'https://x/a.jpg');
      },
    );
  });

  group('getContinueReading', () {
    Future<void> read(String id, UserBook p) async {
      await repo.saveProgress(p);
      await repo.saveReadingSnapshot(_book(id));
    }

    test('nothing read yet is empty', () async {
      expect(await repo.getContinueReading(), isEmpty);
    });

    test(
      'returns started books, most recently read first, with progress',
      () async {
        await read('old', _progress('old', minute: 1));
        await read('new', _progress('new', page: 50, minute: 9));
        await read('mid', _progress('mid', minute: 4));

        final list = await repo.getContinueReading();
        expect(list.map((e) => e.book.id), ['new', 'mid', 'old']);
        expect(list.first.percent, 50);
        expect(list.first.book.title, 'Title new');
      },
    );

    test('leaves out unopened, finished and never-read books', () async {
      await read('keep', _progress('keep'));
      await read('page0', _progress('page0', page: 0));
      await read('done', _progress('done', page: 99, total: 100));
      await read('never', _progress('never', read: false));
      await read('nopages', _progress('nopages', total: 0));
      expect((await repo.getContinueReading()).map((e) => e.book.id), ['keep']);
    });

    test('falls back to the saved copy when no snapshot exists', () async {
      await repo.saveProgress(_progress('s'));
      await repo.saveBook(_book('s'));
      expect((await repo.getContinueReading()).single.book.id, 's');
    });

    test('a book with no stored copy at all is skipped', () async {
      await repo.saveProgress(_progress('ghost'));
      expect(await repo.getContinueReading(), isEmpty);
    });

    test('honours the limit', () async {
      for (var i = 0; i < 8; i++) {
        await read('b$i', _progress('b$i', minute: i));
      }
      expect(await repo.getContinueReading(limit: 3), hasLength(3));
    });

    test('a snapshot is not mistaken for a progress record', () async {
      await repo.saveReadingSnapshot(_book('only-snapshot'));
      expect(await repo.getAllProgress(), isEmpty);
    });

    test('one corrupt progress record does not hide the others', () async {
      SharedPreferences.setMockInitialValues({
        'book_progress_bad': 'not json',
        'book_progress_good':
            '{"book_id":"good","current_page":10,"total_pages":100,'
            '"reading_progress":0.1,"last_read_at":"2026-10-23T09:00:00.000"}',
        'book_reading_data_good':
            '{"id":"good","title":"Good book","cefr_level":"A2"}',
      });
      final list = await BookRepository().getContinueReading();
      expect(list.map((e) => e.book.id), ['good']);
    });
  });
}
