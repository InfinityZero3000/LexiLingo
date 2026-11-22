import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:lexilingo_app/core/services/skill_event_recorder.dart';
import 'package:lexilingo_app/features/level/domain/entities/proficiency_entity.dart';
import 'package:lexilingo_app/features/level/presentation/providers/proficiency_provider.dart';
import 'package:lexilingo_app/features/mistakes/data/mistake_notebook_repository.dart';
import 'package:lexilingo_app/features/mistakes/domain/mistake_notebook_entry.dart';

import '../../data/repositories/book_repository.dart';
import '../../domain/entities/book_entities.dart';
import 'package:lexilingo_app/core/state/reset_epoch.dart';

/// Reader pages per quiz section; the last section may be shorter.
const int kPagesPerQuizSection = 10;

/// Longest excerpt sent to the quiz generator.
const int kQuizExcerptChars = 1800;

enum QuizAccessKind { locked, take, review }

/// What the book detail's quiz button should do.
class QuizAccess {
  const QuizAccess(this.kind, [this.section]);

  final QuizAccessKind kind;
  final int? section;

  @override
  bool operator ==(Object other) =>
      other is QuizAccess && other.kind == kind && other.section == section;

  @override
  int get hashCode => Object.hash(kind, section);
}

/// Pure section arithmetic. Section k (1-based) covers pages
/// [(k-1)*kPagesPerQuizSection, k*kPagesPerQuizSection).
abstract final class QuizSections {
  static int count(int totalPages) => totalPages <= 0
      ? 0
      : (totalPages + kPagesPerQuizSection - 1) ~/ kPagesPerQuizSection;

  static int sectionOfPage(int page) => page ~/ kPagesPerQuizSection + 1;

  /// First page of section [k].
  static int startPage(int k) => (k - 1) * kPagesPerQuizSection;

  /// One past the last page of section [k].
  static int endPage(int k, int totalPages) {
    final end = k * kPagesPerQuizSection;
    return end > totalPages ? totalPages : end;
  }

  /// The page that, once reached, completes section [k]: the first page of
  /// the next section, or the final page for the last section.
  static int unlockPage(int k, int totalPages) =>
      k >= count(totalPages) ? totalPages - 1 : k * kPagesPerQuizSection;

  static bool isUnlocked(int k, int furthestPage, int totalPages) =>
      k >= 1 &&
      k <= count(totalPages) &&
      furthestPage >= unlockPage(k, totalPages);

  static int unlockedCount(int furthestPage, int totalPages) {
    var n = 0;
    while (isUnlocked(n + 1, furthestPage, totalPages)) {
      n++;
    }
    return n;
  }

  static QuizAccess access(int furthestPage, int totalPages, Set<int> done) {
    final unlocked = unlockedCount(furthestPage, totalPages);
    if (unlocked == 0) return const QuizAccess(QuizAccessKind.locked);
    for (var k = unlocked; k >= 1; k--) {
      if (!done.contains(k)) return QuizAccess(QuizAccessKind.take, k);
    }
    return QuizAccess(QuizAccessKind.review, unlocked);
  }

  /// Deterministic text for the generator: the whole section when it fits,
  /// otherwise the opening of its first, middle and last pages so the quiz
  /// spans what was read. Stable input keeps the quiz cache key stable.
  static String excerpt(List<String> sectionPages) {
    final pages = [
      for (final p in sectionPages)
        if (p.trim().isNotEmpty) p.trim(),
    ];
    if (pages.isEmpty) return '';
    final joined = pages.join('\n\n');
    if (joined.length <= kQuizExcerptChars) return joined;
    final picks = <int>{0, pages.length ~/ 2, pages.length - 1}.toList()
      ..sort();
    final each = kQuizExcerptChars ~/ picks.length;
    final parts = [
      for (final i in picks)
        pages[i].length > each ? pages[i].substring(0, each) : pages[i],
    ];
    return parts.join('\n\n');
  }
}

/// State management for the Book Reading feature.
///
/// Phase 5: Book Reading.
class BookProvider extends ChangeNotifier with ResetEpoch {
  final BookRepository _repository;
  final MistakeNotebookRepository _mistakeRepository;
  final SkillEventRecorder _skillRecorder;

  BookProvider({
    BookRepository? repository,
    MistakeNotebookRepository? mistakeRepository,
    SkillEventRecorder? skillRecorder,
  }) : _repository = repository ?? BookRepository(),
       _mistakeRepository =
           mistakeRepository ?? const MistakeNotebookRepository(),
       _skillRecorder = skillRecorder ?? const SkillEventRecorder();

  // ── State ──────────────────────────────────────────────────

  List<Book> _recommendedBooks = [];
  List<Book> _searchResults = [];
  String? _selectedCefrLevel;

  // Per-level browse books (lazy horizontal scroll)
  final Map<String, List<Book>> _levelBooks = {};
  final Map<String, int> _levelPage = {};
  final Map<String, bool> _levelLoadingMore = {};
  final Map<String, bool> _levelHasMore = {};
  String? _selectedTopic;

  /// All browsable genre labels.
  static const List<String> kTopics = [
    'Children',
    'Fantasy',
    'Mystery',
    'Romance',
    'Adventure',
    'Fiction',
    'History',
    'Science Fiction',
    'Philosophy',
    'Poetry',
  ];

  Book? _currentBook;
  String? _bookText; // Loaded plain-text content
  List<String> _pages = []; // Text split into pages
  int _currentPage = 0;

  List<Bookmark> _bookmarks = [];
  UserBook? _currentProgress;
  ReaderSettings _readerSettings = const ReaderSettings();

  BookQuiz? _currentQuiz;
  bool _quizCompleted = false;
  int _quizScore = 0;

  bool _isLoading = false;
  bool _isQuizLoading = false;
  String? _quizError;
  bool _isSearching = false;
  bool _isDownloading = false;
  String? _downloadedPath;
  String? _error;

  List<Book> _savedBooks = [];
  List<ReadingEntry> _continueReading = [];
  final Set<String> _snapshotted = {};

  Timer? _searchDebounce;
  final Set<String> _awardedMilestones = {};

  // ── Getters ────────────────────────────────────────────────

  List<Book> get recommendedBooks => _recommendedBooks;
  List<Book> get searchResults => _searchResults;
  String? get selectedCefrLevel => _selectedCefrLevel;
  String? get selectedTopic => _selectedTopic;

  bool isLoadingMoreForLevel(String level) => _levelLoadingMore[level] ?? false;
  bool hasMoreForLevel(String level) => _levelHasMore[level] ?? true;

  /// Curated + browse books for [level], deduplicated by id.
  List<Book> booksForLevel(String level) {
    final curated = _recommendedBooks
        .where((b) => b.cefrLevel == level)
        .where((b) => _selectedTopic == null || b.topic == _selectedTopic)
        .toList();
    final browse = _levelBooks[level] ?? [];
    final seen = <String>{};
    final result = <Book>[];
    for (final b in [...curated, ...browse]) {
      if (seen.add(b.id)) result.add(b);
    }
    return result;
  }

  Book? get currentBook => _currentBook;

  /// True when the last [openBook] could not load the book's progress.
  bool get openFailed => _openFailed;
  bool _openFailed = false;
  String? get bookText => _bookText;
  List<String> get pages => _pages;
  int get currentPage => _currentPage;
  int get totalPages => _pages.length;

  /// Pages of the open book: the loaded text, else what progress recorded.
  int get quizTotalPages =>
      _pages.isNotEmpty ? _pages.length : (_currentProgress?.totalPages ?? 0);

  int get furthestPage {
    final saved = _currentProgress?.furthestPage ?? 0;
    return _currentPage > saved ? _currentPage : saved;
  }

  Set<int> get completedQuizSections =>
      (_currentProgress?.quizSectionsDone ?? const <int>[]).toSet();

  QuizAccess get quizAccess =>
      QuizSections.access(furthestPage, quizTotalPages, completedQuizSections);

  List<Bookmark> get bookmarks => _bookmarks;
  UserBook? get currentProgress => _currentProgress;
  ReaderSettings get readerSettings => _readerSettings;

  BookQuiz? get currentQuiz => _currentQuiz;
  bool get quizCompleted => _quizCompleted;
  int get quizScore => _quizScore;

  bool get isLoading => _isLoading;
  bool get isQuizLoading => _isQuizLoading;
  String? get quizError => _quizError;
  bool get isSearching => _isSearching;
  bool get isDownloading => _isDownloading;
  String? get downloadedPath => _downloadedPath;
  String? get error => _error;
  List<Book> get savedBooks => _savedBooks;
  List<ReadingEntry> get continueReading => _continueReading;

  // ── Book Discovery ─────────────────────────────────────────

  /// Load curated recommended books, optionally filtered by CEFR level.
  Future<void> loadRecommendedBooks({String? cefrLevel}) async {
    final epoch = resetEpoch;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final books = await _repository.getRecommendedBooks(cefrLevel: cefrLevel);
      if (isStale(epoch)) return;
      _recommendedBooks = books;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  int _searchToken = 0;

  /// Search for books with a 400 ms debounce.
  void searchBooks(String query) {
    _searchDebounce?.cancel();

    if (query.length < 2) {
      _searchToken++;
      _isSearching = false;
      _searchResults = [];
      notifyListeners();
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 400), () async {
      final token = ++_searchToken;
      _isSearching = true;
      _error = null;
      notifyListeners();

      try {
        final results = await _repository.searchBooks(
          query: query,
          cefrLevel: _selectedCefrLevel,
        );
        if (token != _searchToken) return;
        _searchResults = results;
      } catch (e) {
        if (token != _searchToken) return;
        _error = e.toString();
        _searchResults = [];
      } finally {
        if (token == _searchToken) {
          _isSearching = false;
          notifyListeners();
        }
      }
    });
  }

  void clearSearch() {
    _searchDebounce?.cancel();
    _searchToken++;
    _isSearching = false;
    _searchResults = [];
    notifyListeners();
  }

  void setCefrFilter(String? level) {
    _selectedCefrLevel = level;
    notifyListeners();
  }

  void setTopicFilter(String? topic) {
    _selectedTopic = topic;
    // Reset per-level browse state so next scroll re-fetches with new topic
    _levelBooks.clear();
    _levelPage.clear();
    _levelHasMore.clear();
    notifyListeners();
  }

  /// Load more books for [level] by fetching the next browse page.
  /// Called when the user scrolls near the end of a level's horizontal list.
  Future<void> loadMoreForLevel(String level) async {
    if (_levelLoadingMore[level] == true) return;
    if (_levelHasMore[level] == false) return;

    final epoch = resetEpoch;
    _levelLoadingMore[level] = true;
    notifyListeners();

    final nextPage = (_levelPage[level] ?? 0) + 1;
    final topic = _selectedTopic;
    try {
      final books = await _repository.browseByLevel(
        level: level,
        page: nextPage,
        topic: topic,
      );
      // The topic filter clears every level's pages; a reply for the old
      // topic would otherwise be appended to the new topic's shelf.
      if (topic != _selectedTopic || isStale(epoch)) return;
      final have = {for (final b in _levelBooks[level] ?? const <Book>[]) b.id};
      _levelBooks[level] = [
        ...(_levelBooks[level] ?? []),
        ...books.where((b) => !have.contains(b.id)),
      ];
      _levelPage[level] = nextPage;
      _levelHasMore[level] = books.isNotEmpty;
    } catch (_) {
      // Silently ignore — curated books remain visible
    } finally {
      if (!isStale(epoch)) {
        _levelLoadingMore[level] = false;
        notifyListeners();
      }
    }
  }

  // ── Book Detail & Reader ───────────────────────────────────

  /// Set the active book and load its progress + bookmarks.
  Future<void> openBook(Book book) async {
    _currentBook = book;
    _bookText = null;
    _pages = [];
    _currentPage = 0;
    _bookmarks = [];
    _currentProgress = null;
    _downloadedPath = null;
    _error = null;
    _openFailed = false;
    notifyListeners();

    // Load saved progress and bookmarks in parallel
    final List<Object?> results;
    try {
      results = await Future.wait<Object?>([
        _repository.getProgress(book.id),
        _repository.getBookmarks(book.id),
        _repository.getDownloadedPath(book.id),
      ]);
    } catch (e) {
      if (_currentBook?.id != book.id) return;
      _error = e.toString();
      _openFailed = true;
      notifyListeners();
      return;
    }

    if (_currentBook?.id != book.id) return;
    _currentProgress = results[0] as UserBook?;
    _bookmarks = (results[1] as List<Bookmark>?) ?? [];
    _downloadedPath = results[2] as String?;

    // Restore page from saved progress
    if (_currentProgress != null) {
      _currentPage = _currentProgress!.currentPage;
    }
    notifyListeners();
  }

  /// Load the book text content (from local file if downloaded, else HTTP).
  Future<void> loadBookText({int charsPerPage = 2000}) async {
    final book = _currentBook;
    if (book == null) return;

    final epoch = resetEpoch;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _loadText(book, charsPerPage, epoch);
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
    } finally {
      if (!isStale(epoch)) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadText(Book book, int charsPerPage, int epoch) async {
    var text = await _repository.fetchBookText(book);
    if (isStale(epoch)) return;

    // Strip Project Gutenberg header/footer boilerplate
    text = _stripGutenbergBoilerplate(text);

    // Normalize Gutenberg's plain-text ALL CAPS convention to readable case
    text = _normalizeGutenbergFormatting(text);

    _bookText = text;
    _pages = _paginateText(text, charsPerPage: charsPerPage);

    // Restore reading position
    if (_currentPage >= _pages.length) {
      _currentPage = 0;
    }
  }

  String _stripGutenbergBoilerplate(String text) {
    const startMarker = '*** START OF THE PROJECT GUTENBERG EBOOK';
    const endMarker = '*** END OF THE PROJECT GUTENBERG EBOOK';
    final startIdx = text.indexOf(startMarker);
    final endIdx = text.indexOf(endMarker);
    if (startIdx != -1) {
      // Skip past the marker line itself
      final afterMarker = text.indexOf('\n', startIdx) + 1;
      final bodyEnd = endIdx != -1 ? endIdx : text.length;
      var body = text.substring(afterMarker, bodyEnd).trim();

      // Skip Gutenberg's title/TOC block: look for the first actual paragraph
      // which follows a blank line and is not entirely uppercase.
      // Gutenberg books often have 20-50 lines of title/production notes first.
      final lines = body.split('\n');
      var contentStart = 0;
      int blankCount = 0;
      for (var i = 0; i < lines.length && i < 200; i++) {
        final line = lines[i].trim();
        if (line.isEmpty) {
          blankCount++;
        } else {
          // A "content" line: mixed case, longer than 40 chars (real prose)
          final letters = line.replaceAll(RegExp(r'[^A-Za-z]'), '');
          if (letters.length > 40 && blankCount >= 1) {
            final upperCount = letters
                .split('')
                .where((c) => c == c.toUpperCase())
                .length;
            final upperRatio = upperCount / letters.length;
            if (upperRatio < 0.7) {
              contentStart = lines.sublist(0, i).join('\n').length;
              break;
            }
          }
          blankCount = 0;
        }
      }
      if (contentStart > 0) {
        body = body.substring(contentStart).trim();
      }

      return body;
    }
    return text.trim();
  }

  // Regex for Roman numerals (I–XXXIX range sufficient for chapters)
  static final _romanNumeralRe = RegExp(
    r'^M{0,4}(CM|CD|D?C{0,3})(XC|XL|L?X{0,3})(IX|IV|V?I{0,3})$',
  );

  /// Convert all-caps words (2+ letters) to title case.
  ///
  /// Project Gutenberg plain-text files use ALL CAPS for chapter headings and
  /// section titles. This makes them readable without altering normal prose.
  String _normalizeGutenbergFormatting(String text) {
    return text.replaceAllMapped(RegExp(r'\b[A-Z]{2,}\b'), (match) {
      final word = match.group(0)!;
      // Preserve valid Roman numerals so "Chapter II" stays "Chapter II"
      if (_romanNumeralRe.hasMatch(word)) return word;
      return word[0] + word.substring(1).toLowerCase();
    });
  }

  List<String> _paginateText(String text, {required int charsPerPage}) {
    if (text.isEmpty) return [''];
    final pages = <String>[];
    var offset = 0;
    while (offset < text.length) {
      var end = (offset + charsPerPage).clamp(0, text.length);
      // Snap to a paragraph boundary (double newline) within ±200 chars of
      // the target end, but never before the current page start.
      if (end < text.length) {
        final searchFrom = (end - 200).clamp(offset + 1, text.length).toInt();
        final nextNewline = text.indexOf('\n\n', searchFrom);
        if (nextNewline != -1 && nextNewline <= end + 200) {
          end = nextNewline + 2;
        }
      }
      // Guard: ensure we always advance at least one character
      if (end <= offset) {
        end = (offset + charsPerPage).clamp(offset + 1, text.length);
      }
      pages.add(text.substring(offset, end).trim());
      offset = end;
    }
    return pages;
  }

  /// Navigate to an absolute [page] and save progress.
  Future<void> goToPage(int page) async {
    if (_pages.isEmpty) return;
    _currentPage = page.clamp(0, _pages.length - 1);
    notifyListeners();
    await _saveProgress();
  }

  Future<void> nextPage() => goToPage(_currentPage + 1);
  Future<void> previousPage() => goToPage(_currentPage - 1);

  Future<void> _saveProgress() async {
    final book = _currentBook;
    if (book == null || _pages.isEmpty) return;

    final progress = (_currentProgress ?? UserBook(bookId: book.id)).copyWith(
      currentPage: _currentPage,
      totalPages: _pages.length,
      readingProgress: _currentPage / _pages.length,
      lastReadAt: DateTime.now(),
      furthestPage: furthestPage,
    );
    _currentProgress = progress;
    await _repository.saveProgress(progress);
    if (_snapshotted.add(book.id)) await _repository.saveReadingSnapshot(book);

    // Award reading milestone XP (fire-and-forget; backend dedup prevents doubles)
    final pct = _pages.length > 1 ? _currentPage / (_pages.length - 1) : 1.0;
    if (pct >= 0.5) {
      _tryAwardMilestone('${book.id}_50pct', 10, 'reading_50pct');
    }
    if (_currentPage == _pages.length - 1) {
      _tryAwardMilestone('${book.id}_100pct', 20, 'reading_complete');
    }
  }

  void _tryAwardMilestone(String key, int xp, String detail) {
    if (_awardedMilestones.contains(key)) return;
    _awardedMilestones.add(key);
    _repository.awardXP(
      baseXp: xp,
      sourceId: 'book_milestone_$key',
      sourceDetail: detail,
    );
  }

  // ── Bookmarks ──────────────────────────────────────────────

  Future<void> toggleBookmark() async {
    final book = _currentBook;
    if (book == null) return;

    final epoch = resetEpoch;
    final isMarked = await _repository.isBookmarked(book.id, _currentPage);
    if (isStale(epoch)) return;
    if (isMarked) {
      await _repository.removeBookmark(book.id, _currentPage);
    } else {
      await _repository.addBookmark(
        Bookmark(
          id: '${book.id}_page_$_currentPage',
          bookId: book.id,
          page: _currentPage,
          createdAt: DateTime.now(),
        ),
      );
    }
    final marks = await _repository.getBookmarks(book.id);
    if (isStale(epoch)) return;
    _bookmarks = marks;
    notifyListeners();
  }

  Future<bool> isCurrentPageBookmarked() async {
    final book = _currentBook;
    if (book == null) return false;
    return _repository.isBookmarked(book.id, _currentPage);
  }

  // ── Reader Settings ────────────────────────────────────────

  Future<void> loadReaderSettings() async {
    _readerSettings = await _repository.getReaderSettings();
    notifyListeners();
  }

  Future<void> updateReaderSettings(ReaderSettings settings) async {
    _readerSettings = settings;
    notifyListeners();
    await _repository.saveReaderSettings(settings);
  }

  // ── Offline Download ───────────────────────────────────────

  Future<void> downloadBook() async {
    final book = _currentBook;
    if (book == null) return;

    final epoch = resetEpoch;
    _isDownloading = true;
    _error = null;
    notifyListeners();

    try {
      final path = await _repository.downloadBook(book);
      if (isStale(epoch)) return;
      _downloadedPath = path;
    } catch (e) {
      if (isStale(epoch)) return;
      _error = e.toString();
      debugPrint('BookProvider.downloadBook: $e');
    } finally {
      if (!isStale(epoch)) {
        _isDownloading = false;
        notifyListeners();
      }
    }
  }

  // ── Quiz ───────────────────────────────────────────────────

  int _quizLoadToken = 0;
  int _quizSection = 1;

  /// Loads the quiz for [section], first loading the book text if it is not
  /// here yet: a quiz is only ever built from what the section says.
  Future<void> loadChapterQuiz(int section) async {
    final book = _currentBook;
    if (book == null) return;

    final token = ++_quizLoadToken;
    _quizSection = section;
    _isQuizLoading = true;
    _currentQuiz = null;
    _quizCompleted = false;
    _quizScore = 0;
    _quizError = null;
    notifyListeners();

    try {
      if (_pages.isEmpty) {
        await _loadText(book, 2000, resetEpoch);
        if (token != _quizLoadToken) return;
        if (_pages.isEmpty) {
          _quizError = 'Book text unavailable';
          return;
        }
      }
      final total = _pages.length;
      final excerpt = QuizSections.excerpt(
        _pages.sublist(
          QuizSections.startPage(section).clamp(0, total),
          QuizSections.endPage(section, total),
        ),
      );
      if (excerpt.isEmpty) {
        _quizError = 'Section has no text';
        return;
      }
      final quiz = await _repository.getChapterQuiz(
        bookId: book.id,
        chapter: section,
        book: book,
        chapterExcerpt: excerpt,
      );
      if (token != _quizLoadToken) return;
      _currentQuiz = quiz;
    } catch (e) {
      if (token != _quizLoadToken) return;
      _quizError = e.toString();
    } finally {
      if (token == _quizLoadToken) {
        _isQuizLoading = false;
        notifyListeners();
      }
    }
  }

  void submitQuizAnswer(int questionIndex, int selectedIndex) {
    final quiz = _currentQuiz;
    if (quiz == null || questionIndex >= quiz.questions.length) return;
    final question = quiz.questions[questionIndex];
    final isCorrect = question.correctIndex == selectedIndex;
    if (isCorrect) {
      _quizScore++;
    } else {
      unawaited(_saveQuizMistake(quiz, question, questionIndex, selectedIndex));
    }
    // A book comprehension question is reading evidence either way — the
    // wrong ones already went to the notebook, but both outcomes have to
    // reach the skill score or accuracy is only ever measured from failures.
    unawaited(
      _skillRecorder.record([
        ExerciseResultData(
          exerciseType: 'book_quiz',
          skill: SkillType.reading,
          difficultyLevel: normalizeCefrLevel(_currentBook?.cefrLevel),
          isCorrect: isCorrect,
          score: isCorrect ? 100 : 0,
        ),
      ]),
    );
    notifyListeners();
  }

  Future<void> _saveQuizMistake(
    BookQuiz quiz,
    BookQuizQuestion question,
    int questionIndex,
    int selectedIndex,
  ) async {
    final selectedAnswer = _optionText(question.options, selectedIndex);
    final correctAnswer = _optionText(question.options, question.correctIndex);

    await _mistakeRepository.saveMistake(
      MistakeNotebookEntry(
        id: MistakeNotebookEntry.buildId(
          sourceType: 'book_quiz',
          sourceId: quiz.bookId,
          questionId: question.id.isEmpty
              ? 'part$_quizSection:$questionIndex'
              : 'part$_quizSection:${question.id}',
        ),
        sourceType: 'book_quiz',
        sourceId: quiz.bookId,
        sourceTitle: _currentBook?.title ?? 'Book quiz',
        question: question.question,
        selectedAnswer: selectedAnswer,
        correctAnswer: correctAnswer,
        explanation: question.explanation,
        skill: 'reading',
        createdAt: DateTime.now(),
      ),
    );
  }

  String _optionText(List<String> options, int index) {
    if (index < 0 || index >= options.length) return '';
    return options[index];
  }

  /// One XP award per section, ever: /xp/award dedups on this id. Keeps the
  /// pre-sections `_ch<n>` format so earlier awards still dedup.
  static String quizSourceId(String bookId, int section) =>
      'book_quiz_${bookId}_ch$section';

  void completeQuiz() {
    if (_quizCompleted) return;
    _quizCompleted = true;
    notifyListeners();
    unawaited(_markSectionDone(_quizSection));

    // Award XP proportional to score (fire-and-forget)
    final quiz = _currentQuiz;
    if (quiz != null && quiz.questions.isNotEmpty && _quizScore > 0) {
      final xp = (quiz.xpReward * _quizScore / quiz.questions.length)
          .round()
          .clamp(5, quiz.xpReward);
      unawaited(
        _repository.awardXP(
          baseXp: xp,
          sourceId: quizSourceId(quiz.bookId, _quizSection),
          sourceDetail: 'chapter_quiz',
        ),
      );
    }
  }

  Future<void> _markSectionDone(int section) async {
    final book = _currentBook;
    if (book == null) return;
    final base =
        _currentProgress ??
        UserBook(bookId: book.id, totalPages: quizTotalPages);
    if (base.quizSectionsDone.contains(section)) return;
    final updated = base.copyWith(
      quizSectionsDone: [...base.quizSectionsDone, section]..sort(),
      furthestPage: furthestPage,
    );
    _currentProgress = updated;
    notifyListeners();
    try {
      await _repository.saveProgress(updated);
    } catch (e) {
      debugPrint('BookProvider: could not save quiz section: $e');
    }
  }

  // ── Continue reading ───────────────────────────────────────

  Future<void> loadContinueReading() async {
    final epoch = resetEpoch;
    try {
      final shelf = await _repository.getContinueReading();
      if (isStale(epoch)) return;
      _continueReading = shelf;
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to load continue reading: $e');
    }
  }

  // ── Saved Books ────────────────────────────────────────────

  Future<void> loadSavedBooks() async {
    final epoch = resetEpoch;
    final saved = await _repository.getSavedBooks();
    if (isStale(epoch)) return;
    _savedBooks = saved;
    notifyListeners();
  }

  bool isBookSaved(String bookId) => _savedBooks.any((b) => b.id == bookId);

  Future<void> toggleSaveBook(Book book) async {
    final epoch = resetEpoch;
    if (isBookSaved(book.id)) {
      await _repository.unsaveBook(book.id);
      if (isStale(epoch)) return;
      _savedBooks = _savedBooks.where((b) => b.id != book.id).toList();
    } else {
      await _repository.saveBook(book);
      if (isStale(epoch)) return;
      if (!_savedBooks.any((b) => b.id == book.id)) {
        _savedBooks = [..._savedBooks, book];
      }
    }
    notifyListeners();
  }

  // ── Cleanup ────────────────────────────────────────────────

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void reset() {
    bumpResetEpoch();
    _searchDebounce?.cancel();
    _searchToken++;
    _quizLoadToken++;
    _recommendedBooks = [];
    _searchResults = [];
    _selectedCefrLevel = null;
    _selectedTopic = null;
    _levelBooks.clear();
    _levelPage.clear();
    _levelLoadingMore.clear();
    _levelHasMore.clear();
    _currentBook = null;
    _bookText = null;
    _pages = [];
    _currentPage = 0;
    _bookmarks = [];
    _currentProgress = null;
    _currentQuiz = null;
    _quizCompleted = false;
    _quizScore = 0;
    _isLoading = false;
    _isQuizLoading = false;
    _quizError = null;
    _isSearching = false;
    _isDownloading = false;
    _downloadedPath = null;
    _error = null;
    _openFailed = false;
    _savedBooks = [];
    _continueReading = [];
    _snapshotted.clear();
    _awardedMilestones.clear();
    notifyListeners();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }
}
