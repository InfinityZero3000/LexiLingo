/// Tests for Book entity models — Phase 5
///
/// Covers: CefrInfo, Book, UserBook, Bookmark,
///         BookQuizQuestion, BookQuiz, ReaderSettings, ReaderTheme

import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';

void main() {
  // =========================================================================
  // CefrInfo
  // =========================================================================
  group('CefrInfo', () {
    test('fromJson parses label and color', () {
      final info = CefrInfo.fromJson({'label': 'Beginner', 'color': '#4CAF50'});
      expect(info.label, 'Beginner');
      expect(info.color, '#4CAF50');
    });

    test('fromJson defaults label to empty string when missing', () {
      final info = CefrInfo.fromJson({'color': '#FFC107'});
      expect(info.label, '');
    });

    test('fromJson defaults color to #FFC107 when missing', () {
      final info = CefrInfo.fromJson({'label': 'Intermediate'});
      expect(info.color, '#FFC107');
    });
  });

  // =========================================================================
  // Book
  // =========================================================================
  group('Book', () {
    final fullJson = {
      'id': 'gutenberg-11',
      'source': 'gutenberg',
      'title': "Alice's Adventures in Wonderland",
      'author': 'Lewis Carroll',
      'description': 'A girl follows a rabbit into a fantastical world.',
      'cover_url': 'https://example.com/cover.jpg',
      'download_url': 'https://gutenberg.org/ebooks/11.txt',
      'language': 'en',
      'cefr_level': 'A2',
      'cefr_info': {'label': 'Elementary', 'color': '#8BC34A'},
      'subject': 'Fantasy',
      'download_count': 50000,
      'chapter_count': 12,
      'word_count': 26500,
    };

    test('fromJson parses all fields correctly', () {
      final book = Book.fromJson(fullJson);
      expect(book.id, 'gutenberg-11');
      expect(book.source, 'gutenberg');
      expect(book.title, "Alice's Adventures in Wonderland");
      expect(book.author, 'Lewis Carroll');
      expect(book.cefrLevel, 'A2');
      expect(book.chapterCount, 12);
      expect(book.wordCount, 26500);
      expect(book.downloadCount, 50000);
    });

    test('fromJson parses cefrInfo when present', () {
      final book = Book.fromJson(fullJson);
      expect(book.cefrInfo, isNotNull);
      expect(book.cefrInfo!.label, 'Elementary');
      expect(book.cefrInfo!.color, '#8BC34A');
    });

    test('fromJson handles null cefr_info as null', () {
      final json = Map<String, dynamic>.from(fullJson)..remove('cefr_info');
      final book = Book.fromJson(json);
      expect(book.cefrInfo, isNull);
    });

    test('fromJson defaults cefr_level to B1 when missing', () {
      final book = Book.fromJson({'id': 'test', 'title': 'Test Book'});
      expect(book.cefrLevel, 'B1');
    });

    test('fromJson defaults source to gutenberg when missing', () {
      final book = Book.fromJson({'id': 'test', 'title': 'Test Book'});
      expect(book.source, 'gutenberg');
    });

    test('fromJson defaults language to en when missing', () {
      final book = Book.fromJson({'id': 'test', 'title': 'Test Book'});
      expect(book.language, 'en');
    });

    test('fromJson defaults author to empty string when missing', () {
      final book = Book.fromJson({'id': 'test', 'title': 'Test Book'});
      expect(book.author, '');
    });

    test('fromJson handles numeric type for download_count', () {
      final json = Map<String, dynamic>.from(fullJson)
        ..['download_count'] = 99999;
      final book = Book.fromJson(json);
      expect(book.downloadCount, 99999);
    });
  });

  // =========================================================================
  // UserBook
  // =========================================================================
  group('UserBook', () {
    final fullJson = {
      'book_id': 'gutenberg-11',
      'current_chapter': 3,
      'current_page': 45,
      'total_pages': 200,
      'reading_progress': 0.225,
      'last_read_at': '2024-01-15T10:30:00.000Z',
    };

    test('fromJson parses all fields', () {
      final ub = UserBook.fromJson(fullJson);
      expect(ub.bookId, 'gutenberg-11');
      expect(ub.currentChapter, 3);
      expect(ub.currentPage, 45);
      expect(ub.totalPages, 200);
      expect(ub.readingProgress, closeTo(0.225, 0.001));
      expect(ub.lastReadAt, isNotNull);
    });

    test('fromJson defaults currentChapter to 1 when missing', () {
      final ub = UserBook.fromJson({'book_id': 'test'});
      expect(ub.currentChapter, 1);
    });

    test('fromJson defaults readingProgress to 0.0 when missing', () {
      final ub = UserBook.fromJson({'book_id': 'test'});
      expect(ub.readingProgress, 0.0);
    });

    test('fromJson handles null last_read_at', () {
      final ub = UserBook.fromJson({'book_id': 'test', 'last_read_at': null});
      expect(ub.lastReadAt, isNull);
    });

    test('toJson roundtrip preserves bookId', () {
      final ub = UserBook.fromJson(fullJson);
      final json = ub.toJson();
      expect(json['book_id'], 'gutenberg-11');
      expect(json['current_chapter'], 3);
      expect(json['reading_progress'], closeTo(0.225, 0.001));
    });

    test('toJson last_read_at is ISO string when set', () {
      final ub = UserBook.fromJson(fullJson);
      final json = ub.toJson();
      expect(json['last_read_at'], isA<String>());
      expect(json['last_read_at'], contains('2024'));
    });

    test('toJson last_read_at is null when not set', () {
      final ub = UserBook.fromJson({'book_id': 'test'});
      final json = ub.toJson();
      expect(json['last_read_at'], isNull);
    });

    test('copyWith updates currentChapter', () {
      final ub = UserBook.fromJson(fullJson);
      final updated = ub.copyWith(currentChapter: 10);
      expect(updated.currentChapter, 10);
      expect(updated.bookId, 'gutenberg-11'); // preserved
    });

    test('copyWith updates readingProgress', () {
      final ub = UserBook.fromJson(fullJson);
      final updated = ub.copyWith(readingProgress: 0.75);
      expect(updated.readingProgress, closeTo(0.75, 0.001));
    });
  });

  // =========================================================================
  // Bookmark
  // =========================================================================
  group('Bookmark', () {
    final fullJson = {
      'id': 'bm-001',
      'book_id': 'gutenberg-11',
      'page': 42,
      'note': 'Important quote here',
      'created_at': '2024-01-15T14:00:00.000Z',
    };

    test('fromJson parses id, bookId, page', () {
      final bm = Bookmark.fromJson(fullJson);
      expect(bm.id, 'bm-001');
      expect(bm.bookId, 'gutenberg-11');
      expect(bm.page, 42);
    });

    test('fromJson parses note', () {
      final bm = Bookmark.fromJson(fullJson);
      expect(bm.note, 'Important quote here');
    });

    test('fromJson defaults note to empty string when missing', () {
      final bm = Bookmark.fromJson({
        'id': 'bm-002', 'book_id': 'test', 'page': 1,
        'created_at': '2024-01-01T00:00:00Z',
      });
      expect(bm.note, '');
    });

    test('fromJson uses now when created_at is null', () {
      final before = DateTime.now();
      final bm = Bookmark.fromJson({
        'id': 'bm-003', 'book_id': 'test', 'page': 5, 'created_at': null,
      });
      expect(bm.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue);
    });

    test('toJson roundtrip preserves page', () {
      final bm = Bookmark.fromJson(fullJson);
      final json = bm.toJson();
      expect(json['page'], 42);
      expect(json['id'], 'bm-001');
      expect(json['note'], 'Important quote here');
    });

    test('toJson includes created_at as ISO string', () {
      final bm = Bookmark.fromJson(fullJson);
      final json = bm.toJson();
      expect(json['created_at'], isA<String>());
      expect(json['created_at'], contains('2024'));
    });
  });

  // =========================================================================
  // BookQuizQuestion
  // =========================================================================
  group('BookQuizQuestion', () {
    final fullJson = {
      'id': 'gutenberg-11_ch1_q1',
      'question': 'What is the main theme?',
      'options': ['Identity', 'Adventure', 'Friendship', 'Conflict'],
      'correct_index': 0,
      'explanation': 'The chapter focuses on identity and self-discovery.',
    };

    test('fromJson parses all fields', () {
      final q = BookQuizQuestion.fromJson(fullJson);
      expect(q.id, 'gutenberg-11_ch1_q1');
      expect(q.question, 'What is the main theme?');
      expect(q.options.length, 4);
      expect(q.correctIndex, 0);
      expect(q.explanation, contains('identity'));
    });

    test('fromJson parses options list correctly', () {
      final q = BookQuizQuestion.fromJson(fullJson);
      expect(q.options[0], 'Identity');
      expect(q.options[3], 'Conflict');
    });

    test('fromJson defaults correctIndex to 0 when missing', () {
      final q = BookQuizQuestion.fromJson({
        'id': 'q1', 'question': 'Q?', 'options': ['A', 'B'],
      });
      expect(q.correctIndex, 0);
    });

    test('fromJson defaults explanation to empty string when missing', () {
      final q = BookQuizQuestion.fromJson({
        'id': 'q1', 'question': 'Q?', 'options': ['A', 'B'], 'correct_index': 1,
      });
      expect(q.explanation, '');
    });

    test('fromJson handles empty options list', () {
      final q = BookQuizQuestion.fromJson({
        'id': 'q1', 'question': 'Q?', 'options': [],
      });
      expect(q.options, isEmpty);
    });
  });

  // =========================================================================
  // BookQuiz
  // =========================================================================
  group('BookQuiz', () {
    final questionJson = {
      'id': 'gutenberg-11_ch1_q1',
      'question': 'What is the main theme?',
      'options': ['A', 'B', 'C', 'D'],
      'correct_index': 0,
      'explanation': 'Explanation text.',
    };

    test('fromJson parses bookId and chapter', () {
      final quiz = BookQuiz.fromJson({
        'book_id': 'gutenberg-11',
        'chapter': 3,
        'questions': [],
        'xp_reward': 25,
      });
      expect(quiz.bookId, 'gutenberg-11');
      expect(quiz.chapter, 3);
    });

    test('fromJson parses questions list', () {
      final quiz = BookQuiz.fromJson({
        'book_id': 'gutenberg-11',
        'chapter': 1,
        'questions': [questionJson, questionJson],
        'xp_reward': 25,
      });
      expect(quiz.questions.length, 2);
      expect(quiz.questions[0], isA<BookQuizQuestion>());
    });

    test('fromJson defaults xpReward to 25 when missing', () {
      final quiz = BookQuiz.fromJson({
        'book_id': 'gutenberg-11', 'chapter': 1, 'questions': [],
      });
      expect(quiz.xpReward, 25);
    });

    test('fromJson handles null questions list', () {
      final quiz = BookQuiz.fromJson({
        'book_id': 'gutenberg-11', 'chapter': 1, 'questions': null,
      });
      expect(quiz.questions, isEmpty);
    });

    test('question inside quiz parses explanation correctly', () {
      final quiz = BookQuiz.fromJson({
        'book_id': 'gutenberg-11',
        'chapter': 1,
        'questions': [questionJson],
        'xp_reward': 25,
      });
      expect(quiz.questions[0].explanation, 'Explanation text.');
    });
  });

  // =========================================================================
  // ReaderTheme
  // =========================================================================
  group('ReaderTheme', () {
    test('has three values: light, sepia, dark', () {
      expect(ReaderTheme.values.length, 3);
    });

    test('name property returns correct strings', () {
      expect(ReaderTheme.light.name, 'light');
      expect(ReaderTheme.sepia.name, 'sepia');
      expect(ReaderTheme.dark.name, 'dark');
    });

    test('values.firstWhere correctly resolves from string', () {
      final theme = ReaderTheme.values.firstWhere(
        (e) => e.name == 'sepia',
        orElse: () => ReaderTheme.light,
      );
      expect(theme, ReaderTheme.sepia);
    });
  });

  // =========================================================================
  // ReaderSettings
  // =========================================================================
  group('ReaderSettings', () {
    test('fromJson parses fontSize', () {
      final s = ReaderSettings.fromJson({
        'font_size': 20.0, 'theme': 'light', 'line_spacing': 1.5,
      });
      expect(s.fontSize, closeTo(20.0, 0.001));
    });

    test('fromJson parses lineSpacing', () {
      final s = ReaderSettings.fromJson({
        'font_size': 17.0, 'theme': 'sepia', 'line_spacing': 1.8,
      });
      expect(s.lineSpacing, closeTo(1.8, 0.001));
    });

    test('fromJson parses theme light', () {
      final s = ReaderSettings.fromJson({'theme': 'light'});
      expect(s.theme, ReaderTheme.light);
    });

    test('fromJson parses theme dark', () {
      final s = ReaderSettings.fromJson({'theme': 'dark'});
      expect(s.theme, ReaderTheme.dark);
    });

    test('fromJson parses theme sepia', () {
      final s = ReaderSettings.fromJson({'theme': 'sepia'});
      expect(s.theme, ReaderTheme.sepia);
    });

    test('fromJson defaults fontSize to 17.0 when missing', () {
      final s = ReaderSettings.fromJson({});
      expect(s.fontSize, closeTo(17.0, 0.001));
    });

    test('fromJson defaults theme to light when unknown string', () {
      final s = ReaderSettings.fromJson({'theme': 'unknown_theme'});
      expect(s.theme, ReaderTheme.light);
    });

    test('fromJson defaults lineSpacing to 1.5 when missing', () {
      final s = ReaderSettings.fromJson({});
      expect(s.lineSpacing, closeTo(1.5, 0.001));
    });

    test('toJson roundtrip preserves fontSize and lineSpacing', () {
      final s = ReaderSettings.fromJson({
        'font_size': 22.0, 'theme': 'sepia', 'line_spacing': 1.6,
      });
      final json = s.toJson();
      expect(json['font_size'], closeTo(22.0, 0.001));
      expect(json['line_spacing'], closeTo(1.6, 0.001));
      expect(json['theme'], 'sepia');
    });

    test('copyWith updates fontSize', () {
      const s = ReaderSettings();
      final updated = s.copyWith(fontSize: 24.0);
      expect(updated.fontSize, closeTo(24.0, 0.001));
      expect(updated.theme, ReaderTheme.light); // preserved
    });

    test('copyWith updates theme', () {
      const s = ReaderSettings();
      final updated = s.copyWith(theme: ReaderTheme.dark);
      expect(updated.theme, ReaderTheme.dark);
      expect(updated.fontSize, closeTo(17.0, 0.001)); // preserved
    });
  });
}
