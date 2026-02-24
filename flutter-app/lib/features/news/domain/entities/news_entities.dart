/// News entity models for the News Reading feature.
///
/// Phase 2: News Reading.

/// A news article with CEFR level grading.
class NewsArticle {
  final String id;
  final String title;
  final String description;
  final String content;
  final String url;
  final String imageUrl;
  final String sourceName;
  final String author;
  final String publishedAt;
  final String category;
  final String provider;
  final String cefrLevel;
  final CefrInfo? cefrInfo;
  final int readingTimeMin;
  final List<String> highlightedWords;

  const NewsArticle({
    required this.id,
    required this.title,
    this.description = '',
    this.content = '',
    this.url = '',
    this.imageUrl = '',
    this.sourceName = '',
    this.author = '',
    this.publishedAt = '',
    this.category = 'general',
    this.provider = '',
    this.cefrLevel = 'B1',
    this.cefrInfo,
    this.readingTimeMin = 1,
    this.highlightedWords = const [],
  });

  factory NewsArticle.fromJson(Map<String, dynamic> json) {
    return NewsArticle(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      content: json['content'] as String? ?? '',
      url: json['url'] as String? ?? '',
      imageUrl: json['image_url'] as String? ?? '',
      sourceName: json['source_name'] as String? ?? '',
      author: json['author'] as String? ?? '',
      publishedAt: json['published_at'] as String? ?? '',
      category: json['category'] as String? ?? 'general',
      provider: json['provider'] as String? ?? '',
      cefrLevel: json['cefr_level'] as String? ?? 'B1',
      cefrInfo: json['cefr_info'] != null
          ? CefrInfo.fromJson(json['cefr_info'] as Map<String, dynamic>)
          : null,
      readingTimeMin: json['reading_time_min'] as int? ?? 1,
      highlightedWords: (json['highlighted_words'] as List<dynamic>?)
              ?.map((w) => w as String)
              .toList() ??
          [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'description': description,
        'content': content,
        'url': url,
        'image_url': imageUrl,
        'source_name': sourceName,
        'author': author,
        'published_at': publishedAt,
        'category': category,
        'provider': provider,
        'cefr_level': cefrLevel,
        'reading_time_min': readingTimeMin,
        'highlighted_words': highlightedWords,
      };
}

/// CEFR level information for display.
class CefrInfo {
  final String label;
  final String color;
  final int maxWords;

  const CefrInfo({
    required this.label,
    required this.color,
    this.maxWords = 0,
  });

  factory CefrInfo.fromJson(Map<String, dynamic> json) {
    return CefrInfo(
      label: json['label'] as String? ?? '',
      color: json['color'] as String? ?? '#FFC107',
      maxWords: json['max_words'] as int? ?? 0,
    );
  }
}

/// News category for filter tabs.
class NewsCategory {
  final String id;
  final String label;
  final String icon;

  const NewsCategory({
    required this.id,
    required this.label,
    required this.icon,
  });

  factory NewsCategory.fromJson(Map<String, dynamic> json) {
    return NewsCategory(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      icon: json['icon'] as String? ?? 'public',
    );
  }
}

/// Quiz question for article comprehension.
class QuizQuestion {
  final int id;
  final String type; // comprehension, vocabulary, grammar
  final String question;
  final List<String> options;
  final int correctIndex;
  final String explanation;

  const QuizQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = '',
  });

  factory QuizQuestion.fromJson(Map<String, dynamic> json) {
    return QuizQuestion(
      id: json['id'] as int? ?? 0,
      type: json['type'] as String? ?? '',
      question: json['question'] as String? ?? '',
      options: (json['options'] as List<dynamic>?)
              ?.map((o) => o as String)
              .toList() ??
          [],
      correctIndex: json['correct_index'] as int? ?? 0,
      explanation: json['explanation'] as String? ?? '',
    );
  }
}

/// A news quiz for an article.
class NewsQuiz {
  final List<QuizQuestion> questions;
  final int totalQuestions;
  final int xpReward;

  const NewsQuiz({
    required this.questions,
    required this.totalQuestions,
    this.xpReward = 15,
  });

  factory NewsQuiz.fromJson(Map<String, dynamic> json) {
    final quizData = json['quiz'] as Map<String, dynamic>? ?? json;
    return NewsQuiz(
      questions: (quizData['questions'] as List<dynamic>?)
              ?.map((q) => QuizQuestion.fromJson(q as Map<String, dynamic>))
              .toList() ??
          [],
      totalQuestions: quizData['total_questions'] as int? ?? 0,
      xpReward: quizData['xp_reward'] as int? ?? 15,
    );
  }
}
