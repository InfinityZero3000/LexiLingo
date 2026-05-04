/// Book entity models for the Book Reading feature.
///
/// Phase 5: Book Reading.
library;

/// CEFR level metadata.
class CefrInfo {
  final String label;
  final String color;

  const CefrInfo({required this.label, required this.color});

  factory CefrInfo.fromJson(Map<String, dynamic> json) => CefrInfo(
    label: json['label'] as String? ?? '',
    color: json['color'] as String? ?? '#FFC107',
  );
}

/// A public-domain book from Gutendex or Open Library.
class Book {
  final String id;
  final String source; // 'gutenberg' | 'open_library' | 'curated'
  final String title;
  final String author;
  final String description;
  final String coverUrl;
  final String downloadUrl;
  final String language;
  final String cefrLevel;
  final CefrInfo? cefrInfo;
  final String subject;
  final String topic;
  final int downloadCount;
  final int chapterCount;
  final int wordCount;

  const Book({
    required this.id,
    this.source = 'gutenberg',
    required this.title,
    this.author = '',
    this.description = '',
    this.coverUrl = '',
    this.downloadUrl = '',
    this.language = 'en',
    this.cefrLevel = 'B1',
    this.cefrInfo,
    this.subject = '',
    this.topic = '',
    this.downloadCount = 0,
    this.chapterCount = 0,
    this.wordCount = 0,
  });

  factory Book.fromJson(Map<String, dynamic> json) => Book(
    id: json['id'] as String? ?? '',
    source: json['source'] as String? ?? 'gutenberg',
    title: json['title'] as String? ?? '',
    author: json['author'] as String? ?? '',
    description: json['description'] as String? ?? '',
    coverUrl: json['cover_url'] as String? ?? '',
    downloadUrl: json['download_url'] as String? ?? '',
    language: json['language'] as String? ?? 'en',
    cefrLevel: json['cefr_level'] as String? ?? 'B1',
    cefrInfo: json['cefr_info'] != null
        ? CefrInfo.fromJson(json['cefr_info'] as Map<String, dynamic>)
        : null,
    subject: json['subject'] as String? ?? '',
    topic: json['topic'] as String? ?? '',
    downloadCount: (json['download_count'] as num?)?.toInt() ?? 0,
    chapterCount: (json['chapter_count'] as num?)?.toInt() ?? 0,
    wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
  );
}

/// The user's reading progress for a specific book.
class UserBook {
  final String bookId;
  final int currentChapter;
  final int currentPage;
  final int totalPages;
  final double readingProgress; // 0.0 – 1.0
  final DateTime? lastReadAt;

  const UserBook({
    required this.bookId,
    this.currentChapter = 1,
    this.currentPage = 0,
    this.totalPages = 0,
    this.readingProgress = 0.0,
    this.lastReadAt,
  });

  UserBook copyWith({
    int? currentChapter,
    int? currentPage,
    int? totalPages,
    double? readingProgress,
    DateTime? lastReadAt,
  }) => UserBook(
    bookId: bookId,
    currentChapter: currentChapter ?? this.currentChapter,
    currentPage: currentPage ?? this.currentPage,
    totalPages: totalPages ?? this.totalPages,
    readingProgress: readingProgress ?? this.readingProgress,
    lastReadAt: lastReadAt ?? this.lastReadAt,
  );

  Map<String, dynamic> toJson() => {
    'book_id': bookId,
    'current_chapter': currentChapter,
    'current_page': currentPage,
    'total_pages': totalPages,
    'reading_progress': readingProgress,
    'last_read_at': lastReadAt?.toIso8601String(),
  };

  factory UserBook.fromJson(Map<String, dynamic> json) => UserBook(
    bookId: json['book_id'] as String? ?? '',
    currentChapter: (json['current_chapter'] as num?)?.toInt() ?? 1,
    currentPage: (json['current_page'] as num?)?.toInt() ?? 0,
    totalPages: (json['total_pages'] as num?)?.toInt() ?? 0,
    readingProgress: (json['reading_progress'] as num?)?.toDouble() ?? 0.0,
    lastReadAt: json['last_read_at'] != null
        ? DateTime.tryParse(json['last_read_at'] as String)
        : null,
  );
}

/// A bookmark saved at a specific page position.
class Bookmark {
  final String id;
  final String bookId;
  final int page;
  final String note;
  final DateTime createdAt;

  const Bookmark({
    required this.id,
    required this.bookId,
    required this.page,
    this.note = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'book_id': bookId,
    'page': page,
    'note': note,
    'created_at': createdAt.toIso8601String(),
  };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
    id: json['id'] as String? ?? '',
    bookId: json['book_id'] as String? ?? '',
    page: (json['page'] as num?)?.toInt() ?? 0,
    note: json['note'] as String? ?? '',
    createdAt: json['created_at'] != null
        ? DateTime.tryParse(json['created_at'] as String) ?? DateTime.now()
        : DateTime.now(),
  );
}

/// A comprehension quiz question for a given chapter.
class BookQuizQuestion {
  final String id;
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const BookQuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  factory BookQuizQuestion.fromJson(Map<String, dynamic> json) =>
      BookQuizQuestion(
        id: json['id'] as String? ?? '',
        question: json['question'] as String? ?? '',
        options:
            (json['options'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
        correctIndex: (json['correct_index'] as num?)?.toInt() ?? 0,
        explanation: json['explanation'] as String? ?? '',
      );
}

/// A chapter quiz for one book chapter.
class BookQuiz {
  final String bookId;
  final int chapter;
  final List<BookQuizQuestion> questions;
  final int xpReward;

  const BookQuiz({
    required this.bookId,
    required this.chapter,
    required this.questions,
    this.xpReward = 25,
  });

  factory BookQuiz.fromJson(Map<String, dynamic> json) => BookQuiz(
    bookId: json['book_id'] as String? ?? '',
    chapter: (json['chapter'] as num?)?.toInt() ?? 1,
    questions:
        (json['questions'] as List<dynamic>?)
            ?.map((e) => BookQuizQuestion.fromJson(e as Map<String, dynamic>))
            .toList() ??
        const [],
    xpReward: (json['xp_reward'] as num?)?.toInt() ?? 25,
  );
}

/// Reader display preferences persisted across sessions.
class ReaderSettings {
  final double fontSize; // 14–28
  final ReaderTheme theme;
  final double lineSpacing; // 1.2–2.0

  const ReaderSettings({
    this.fontSize = 17.0,
    this.theme = ReaderTheme.light,
    this.lineSpacing = 1.5,
  });

  ReaderSettings copyWith({
    double? fontSize,
    ReaderTheme? theme,
    double? lineSpacing,
  }) => ReaderSettings(
    fontSize: fontSize ?? this.fontSize,
    theme: theme ?? this.theme,
    lineSpacing: lineSpacing ?? this.lineSpacing,
  );

  Map<String, dynamic> toJson() => {
    'font_size': fontSize,
    'theme': theme.name,
    'line_spacing': lineSpacing,
  };

  factory ReaderSettings.fromJson(Map<String, dynamic> json) => ReaderSettings(
    fontSize: (json['font_size'] as num?)?.toDouble() ?? 17.0,
    theme: ReaderTheme.values.firstWhere(
      (e) => e.name == (json['theme'] as String?),
      orElse: () => ReaderTheme.light,
    ),
    lineSpacing: (json['line_spacing'] as num?)?.toDouble() ?? 1.5,
  );
}

enum ReaderTheme { light, sepia, dark }
