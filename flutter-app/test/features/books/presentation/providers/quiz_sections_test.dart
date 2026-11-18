import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/books/data/repositories/book_repository.dart';
import 'package:lexilingo_app/features/books/domain/entities/book_entities.dart';
import 'package:lexilingo_app/features/books/presentation/providers/book_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _per = kPagesPerQuizSection;

class _Repo extends BookRepository {
  _Repo({this.progress, this.text = ''});

  UserBook? progress;
  final String text;
  final excerpts = <String?>[];
  final chapters = <int>[];
  final awards = <String>[];
  final saved = <UserBook>[];

  @override
  Future<UserBook?> getProgress(String bookId) async => progress;

  @override
  Future<List<Bookmark>> getBookmarks(String bookId) async => const [];

  @override
  Future<String?> getDownloadedPath(String bookId) async => null;

  @override
  Future<String> fetchBookText(Book book) async => text;

  @override
  Future<void> saveProgress(UserBook p) async => saved.add(p);

  @override
  Future<BookQuiz> getChapterQuiz({
    required String bookId,
    required int chapter,
    Book? book,
    String? chapterExcerpt,
  }) async {
    chapters.add(chapter);
    excerpts.add(chapterExcerpt);
    return BookQuiz(
      bookId: bookId,
      chapter: chapter,
      xpReward: 40,
      questions: const [
        BookQuizQuestion(
          id: 'q',
          question: 'Q?',
          options: ['A', 'B'],
          correctIndex: 0,
        ),
      ],
    );
  }

  @override
  Future<void> awardXP({
    required int baseXp,
    required String sourceId,
    String sourceDetail = 'book_reading',
  }) async => awards.add('$sourceId|$sourceDetail');
}

const _book = Book(id: 'b1', title: 'T');

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('section math', () {
    test('count rounds up, the last section may be short', () {
      expect(QuizSections.count(0), 0);
      expect(QuizSections.count(1), 1);
      expect(QuizSections.count(_per), 1);
      expect(QuizSections.count(_per + 1), 2);
      expect(QuizSections.count(25), 3);
    });

    test('page ranges and the short last section', () {
      expect(QuizSections.startPage(1), 0);
      expect(QuizSections.endPage(1, 25), 10);
      expect(QuizSections.startPage(3), 20);
      expect(QuizSections.endPage(3, 25), 25);
      expect(QuizSections.sectionOfPage(9), 1);
      expect(QuizSections.sectionOfPage(10), 2);
    });

    test('a section unlocks once its end is passed', () {
      expect(QuizSections.isUnlocked(1, 9, 25), isFalse);
      expect(QuizSections.isUnlocked(1, 10, 25), isTrue);
      expect(QuizSections.isUnlocked(2, 19, 25), isFalse);
      expect(QuizSections.isUnlocked(2, 20, 25), isTrue);
    });

    test('the last section unlocks on its final page', () {
      expect(QuizSections.isUnlocked(3, 23, 25), isFalse);
      expect(QuizSections.isUnlocked(3, 24, 25), isTrue);
      expect(QuizSections.isUnlocked(4, 99, 25), isFalse, reason: 'no such');
    });

    test('a single-page book unlocks section 1 on page 0', () {
      expect(QuizSections.isUnlocked(1, 0, 1), isTrue);
    });
  });

  group('access', () {
    test('locked before section 1 is read', () {
      expect(
        QuizSections.access(3, 25, {}),
        const QuizAccess(QuizAccessKind.locked),
      );
    });

    test('offers the latest unlocked section not yet done', () {
      expect(
        QuizSections.access(21, 25, {}),
        const QuizAccess(QuizAccessKind.take, 2),
      );
      expect(
        QuizSections.access(21, 25, {2}),
        const QuizAccess(QuizAccessKind.take, 1),
      );
    });

    test('everything done becomes a review of the latest', () {
      expect(
        QuizSections.access(21, 25, {1, 2}),
        const QuizAccess(QuizAccessKind.review, 2),
      );
    });
  });

  group('excerpt', () {
    test('a short section is sent whole', () {
      expect(QuizSections.excerpt(['one', ' two ']), 'one\n\ntwo');
    });

    test('a long section is sampled from first, middle and last page', () {
      final pages = [for (var i = 0; i < 10; i++) '$i${'x' * 1999}'];
      final out = QuizSections.excerpt(pages);
      expect(out.length, lessThanOrEqualTo(kQuizExcerptChars + 4));
      expect(out, contains('0x'));
      expect(out, contains('5x'));
      expect(out, contains('9x'));
      expect(out, isNot(contains('3x')));
      expect(QuizSections.excerpt(pages), out, reason: 'deterministic');
    });
  });

  group('provider', () {
    test('furthest page survives going back', () async {
      final repo = _Repo(
        progress: const UserBook(
          bookId: 'b1',
          currentPage: 3,
          furthestPage: 12,
          totalPages: 25,
        ),
      );
      final provider = BookProvider(repository: repo);
      await provider.openBook(_book);
      expect(provider.furthestPage, 12);
      expect(provider.quizAccess.section, 1);
    });

    test('old progress without furthestPage falls back to current', () {
      final p = UserBook.fromJson({'book_id': 'b', 'current_page': 14});
      expect(p.furthestPage, 14);
      expect(p.quizSectionsDone, isEmpty);
    });

    test('the quiz is built from the section text, loading it first', () async {
      final text = [
        for (var i = 0; i < 40; i++) 'Page$i ${'lorem ipsum ' * 200}',
      ].join('\n\n');
      final repo = _Repo(
        text: text,
        progress: const UserBook(
          bookId: 'b1',
          currentPage: 12,
          furthestPage: 12,
          totalPages: 3,
        ),
      );
      final provider = BookProvider(repository: repo);
      await provider.openBook(_book);
      expect(provider.pages, isEmpty);

      await provider.loadChapterQuiz(1);

      expect(provider.pages, isNotEmpty);
      expect(repo.chapters, [1]);
      expect(repo.excerpts.single, isNotEmpty);
      expect(provider.currentQuiz, isNotNull);
    });

    test('unloadable text shows an error, not a metadata-only quiz', () async {
      final repo = _Repo(text: '');
      final provider = BookProvider(repository: repo);
      await provider.openBook(_book);

      await provider.loadChapterQuiz(1);

      expect(repo.chapters, isEmpty);
      expect(provider.currentQuiz, isNull);
      expect(provider.quizError, isNotNull);
      expect(provider.error, isNull);
      expect(provider.isQuizLoading, isFalse);
      expect(provider.isLoading, isFalse);
    });

    test('quiz loading leaves the reader flags alone', () async {
      final repo = _Repo(text: 'word ' * 6000);
      final provider = BookProvider(repository: repo);
      await provider.openBook(_book);
      final seen = <List<Object?>>[];
      provider.addListener(
        () => seen.add([provider.isLoading, provider.isQuizLoading]),
      );

      await provider.loadChapterQuiz(1);

      expect(seen.every((s) => s[0] == false), isTrue);
      expect(seen.first[1], isTrue);
      expect(seen.last[1], isFalse);
      expect(provider.currentQuiz, isNotNull);
    });

    test('xp source id is per section and completion is remembered', () async {
      expect(BookProvider.quizSourceId('b1', 2), 'book_quiz_b1_ch2');
      final repo = _Repo(
        text: 'word ' * 6000,
        progress: const UserBook(
          bookId: 'b1',
          currentPage: 9,
          furthestPage: 9,
          totalPages: 15,
        ),
      );
      final provider = BookProvider(repository: repo);
      await provider.openBook(_book);
      await provider.loadChapterQuiz(1);
      provider.submitQuizAnswer(0, 0);
      provider.completeQuiz();
      provider.completeQuiz();
      await Future<void>.delayed(Duration.zero);

      expect(repo.awards, ['book_quiz_b1_ch1|chapter_quiz']);
      expect(provider.completedQuizSections, {1});
      expect(repo.saved.last.quizSectionsDone, [1]);
    });
  });
}
