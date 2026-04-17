import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/news/domain/entities/news_entities.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────────────
  // CefrInfo
  // ─────────────────────────────────────────────────────────────────────────
  group('CefrInfo', () {
    test('parses all fields from JSON', () {
      final json = {
        'label': 'Intermediate',
        'color': '#FFC107',
        'max_words': 350,
      };

      final info = CefrInfo.fromJson(json);

      expect(info.label, 'Intermediate');
      expect(info.color, '#FFC107');
      expect(info.maxWords, 350);
    });

    test('uses default color when missing', () {
      final info = CefrInfo.fromJson({'label': 'B1'});
      expect(info.color, '#FFC107');
    });

    test('uses default maxWords 0 when missing', () {
      final info = CefrInfo.fromJson({'label': 'A1', 'color': '#4CAF50'});
      expect(info.maxWords, 0);
    });

    test('handles null values with defaults', () {
      final info = CefrInfo.fromJson({
        'label': null,
        'color': null,
        'max_words': null,
      });
      expect(info.label, '');
      expect(info.color, '#FFC107');
      expect(info.maxWords, 0);
    });

    test('handles completely empty JSON', () {
      final info = CefrInfo.fromJson({});
      expect(info.label, '');
      expect(info.color, '#FFC107');
      expect(info.maxWords, 0);
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NewsArticle
  // ─────────────────────────────────────────────────────────────────────────
  group('NewsArticle', () {
    group('fromJson', () {
      test('parses all required fields correctly', () {
        final json = {
          'id': 'art001',
          'title': 'AI Breakthrough in Language Learning',
          'description': 'Researchers announced a major development',
          'content': 'Full article content goes here...',
          'url': 'https://example.com/article',
          'image_url': 'https://example.com/img.jpg',
          'source_name': 'TechCrunch',
          'author': 'Jane Doe',
          'published_at': '2024-03-15T10:00:00Z',
          'category': 'technology',
          'provider': 'newsapi',
          'cefr_level': 'B2',
          'cefr_info': {
            'label': 'Upper Intermediate',
            'color': '#FF9800',
            'max_words': 500,
          },
          'reading_time_min': 3,
          'highlighted_words': ['breakthrough', 'linguistic', 'phenomena'],
        };

        final article = NewsArticle.fromJson(json);

        expect(article.id, 'art001');
        expect(article.title, 'AI Breakthrough in Language Learning');
        expect(
          article.description,
          'Researchers announced a major development',
        );
        expect(article.content, 'Full article content goes here...');
        expect(article.url, 'https://example.com/article');
        expect(article.imageUrl, 'https://example.com/img.jpg');
        expect(article.sourceName, 'TechCrunch');
        expect(article.author, 'Jane Doe');
        expect(article.publishedAt, '2024-03-15T10:00:00Z');
        expect(article.category, 'technology');
        expect(article.provider, 'newsapi');
        expect(article.cefrLevel, 'B2');
        expect(article.readingTimeMin, 3);
        expect(article.highlightedWords, [
          'breakthrough',
          'linguistic',
          'phenomena',
        ]);
      });

      test('parses cefrInfo correctly', () {
        final json = {
          'id': 'art002',
          'title': 'Test',
          'cefr_info': {
            'label': 'Advanced',
            'color': '#FF5722',
            'max_words': 800,
          },
        };

        final article = NewsArticle.fromJson(json);

        expect(article.cefrInfo, isNotNull);
        expect(article.cefrInfo!.label, 'Advanced');
        expect(article.cefrInfo!.color, '#FF5722');
        expect(article.cefrInfo!.maxWords, 800);
      });

      test('cefrInfo is null when not provided', () {
        final json = {'id': 'art003', 'title': 'Test'};
        final article = NewsArticle.fromJson(json);
        expect(article.cefrInfo, isNull);
      });

      test('uses default cefrLevel B1 when missing', () {
        final json = {'id': 'art004', 'title': 'Test'};
        final article = NewsArticle.fromJson(json);
        expect(article.cefrLevel, 'B1');
      });

      test('uses default category general when missing', () {
        final json = {'id': 'art005', 'title': 'Test'};
        final article = NewsArticle.fromJson(json);
        expect(article.category, 'general');
      });

      test('uses default readingTimeMin 1 when missing', () {
        final json = {'id': 'art006', 'title': 'Test'};
        final article = NewsArticle.fromJson(json);
        expect(article.readingTimeMin, 1);
      });

      test('handles empty highlighted_words array', () {
        final json = {'id': 'art007', 'title': 'Test', 'highlighted_words': []};
        final article = NewsArticle.fromJson(json);
        expect(article.highlightedWords, isEmpty);
      });

      test('returns empty list when highlighted_words is null', () {
        final json = {
          'id': 'art008',
          'title': 'Test',
          'highlighted_words': null,
        };
        final article = NewsArticle.fromJson(json);
        expect(article.highlightedWords, isEmpty);
      });

      test('handles all null fields with defaults', () {
        final json = {
          'id': null,
          'title': null,
          'description': null,
          'content': null,
          'url': null,
          'image_url': null,
          'source_name': null,
          'author': null,
          'published_at': null,
          'category': null,
          'provider': null,
          'cefr_level': null,
          'cefr_info': null,
          'reading_time_min': null,
          'highlighted_words': null,
        };

        final article = NewsArticle.fromJson(json);

        expect(article.id, '');
        expect(article.title, '');
        expect(article.cefrLevel, 'B1');
        expect(article.category, 'general');
        expect(article.readingTimeMin, 1);
        expect(article.highlightedWords, isEmpty);
        expect(article.cefrInfo, isNull);
      });
    });

    group('toJson', () {
      test('serializes all fields with correct keys', () {
        const article = NewsArticle(
          id: 'art_to_json',
          title: 'Test Serialization',
          description: 'Test description',
          content: 'Full content here',
          url: 'https://example.com',
          imageUrl: 'https://img.jpg',
          sourceName: 'TestSource',
          author: 'Author Name',
          publishedAt: '2024-01-01T00:00:00Z',
          category: 'science',
          provider: 'newsdata',
          cefrLevel: 'C1',
          readingTimeMin: 5,
          highlightedWords: ['algorithm', 'neural', 'network'],
        );

        final json = article.toJson();

        expect(json['id'], 'art_to_json');
        expect(json['title'], 'Test Serialization');
        expect(json['description'], 'Test description');
        expect(json['content'], 'Full content here');
        expect(json['url'], 'https://example.com');
        expect(json['image_url'], 'https://img.jpg');
        expect(json['source_name'], 'TestSource');
        expect(json['author'], 'Author Name');
        expect(json['published_at'], '2024-01-01T00:00:00Z');
        expect(json['category'], 'science');
        expect(json['provider'], 'newsdata');
        expect(json['cefr_level'], 'C1');
        expect(json['reading_time_min'], 5);
        expect(json['highlighted_words'], ['algorithm', 'neural', 'network']);
      });

      test('roundtrip fromJson → toJson preserves data', () {
        final original = {
          'id': 'rt_001',
          'title': 'Roundtrip Article',
          'description': 'Desc',
          'content': 'Content body',
          'url': 'https://rt.com',
          'image_url': 'https://img.rt.com',
          'source_name': 'RoundTrip',
          'author': 'RT Author',
          'published_at': '2024-06-01T12:00:00Z',
          'category': 'health',
          'provider': 'newsapi',
          'cefr_level': 'A2',
          'reading_time_min': 2,
          'highlighted_words': ['beautiful', 'important'],
        };

        final article = NewsArticle.fromJson(original);
        final result = article.toJson();

        expect(result['id'], original['id']);
        expect(result['cefr_level'], original['cefr_level']);
        expect(result['highlighted_words'], original['highlighted_words']);
      });
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NewsCategory
  // ─────────────────────────────────────────────────────────────────────────
  group('NewsCategory', () {
    test('parses all fields from JSON', () {
      final json = {
        'id': 'technology',
        'label': 'Technology',
        'icon': 'devices',
      };

      final category = NewsCategory.fromJson(json);

      expect(category.id, 'technology');
      expect(category.label, 'Technology');
      expect(category.icon, 'devices');
    });

    test('uses default icon public when missing', () {
      final category = NewsCategory.fromJson({
        'id': 'general',
        'label': 'World',
      });
      expect(category.icon, 'public');
    });

    test('handles null values', () {
      final category = NewsCategory.fromJson({
        'id': null,
        'label': null,
        'icon': null,
      });
      expect(category.id, '');
      expect(category.label, '');
      expect(category.icon, 'public');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // QuizQuestion
  // ─────────────────────────────────────────────────────────────────────────
  group('QuizQuestion', () {
    test('parses all fields from JSON', () {
      final json = {
        'id': 3,
        'type': 'vocabulary',
        'question': 'What does "algorithm" mean in this context?',
        'options': [
          'A step-by-step procedure',
          'A type of music',
          'A cooking recipe',
          'A sport',
        ],
        'correct_index': 0,
        'explanation':
            'Algorithm refers to a structured procedure for solving problems',
      };

      final question = QuizQuestion.fromJson(json);

      expect(question.id, 3);
      expect(question.type, 'vocabulary');
      expect(question.question, 'What does "algorithm" mean in this context?');
      expect(question.options.length, 4);
      expect(question.options[0], 'A step-by-step procedure');
      expect(question.correctIndex, 0);
      expect(
        question.explanation,
        'Algorithm refers to a structured procedure for solving problems',
      );
    });

    test('uses default id 0 when missing', () {
      final question = QuizQuestion.fromJson({
        'type': 'comprehension',
        'question': 'Q?',
        'options': [],
        'correct_index': 0,
      });
      expect(question.id, 0);
    });

    test('handles null options with empty list', () {
      final json = {
        'id': 1,
        'type': 'comprehension',
        'question': 'Test?',
        'options': null,
        'correct_index': 0,
      };

      final question = QuizQuestion.fromJson(json);
      expect(question.options, isEmpty);
    });

    test('uses empty explanation string as default', () {
      final json = {
        'id': 1,
        'type': 'grammar',
        'question': 'Which is correct?',
        'options': ['A', 'B'],
        'correct_index': 1,
      };

      final question = QuizQuestion.fromJson(json);
      expect(question.explanation, '');
    });

    test('valid question types are comprehension, vocabulary, grammar', () {
      for (final type in ['comprehension', 'vocabulary', 'grammar']) {
        final question = QuizQuestion.fromJson({
          'id': 1,
          'type': type,
          'question': 'Test?',
          'options': ['A', 'B', 'C', 'D'],
          'correct_index': 0,
        });
        expect(question.type, type);
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // NewsQuiz
  // ─────────────────────────────────────────────────────────────────────────
  group('NewsQuiz', () {
    final sampleQuizJson = {
      'article_id': 'art123',
      'quiz': {
        'questions': [
          {
            'id': 1,
            'type': 'comprehension',
            'question': 'What is the main idea?',
            'options': ['A', 'B', 'C', 'D'],
            'correct_index': 0,
            'explanation': 'Explanation 1',
          },
          {
            'id': 2,
            'type': 'vocabulary',
            'question': 'What does X mean?',
            'options': ['P', 'Q', 'R', 'S'],
            'correct_index': 2,
            'explanation': 'Explanation 2',
          },
        ],
        'total_questions': 2,
        'xp_reward': 15,
      },
    };

    test('parses nested quiz field from backend response', () {
      final quiz = NewsQuiz.fromJson(sampleQuizJson);

      expect(quiz.questions.length, 2);
      expect(quiz.totalQuestions, 2);
      expect(quiz.xpReward, 15);
    });

    test('parses questions correctly', () {
      final quiz = NewsQuiz.fromJson(sampleQuizJson);

      expect(quiz.questions[0].id, 1);
      expect(quiz.questions[0].type, 'comprehension');
      expect(quiz.questions[1].id, 2);
      expect(quiz.questions[1].correctIndex, 2);
    });

    test('uses default xpReward 15 when missing', () {
      final quiz = NewsQuiz.fromJson({
        'quiz': {'questions': [], 'total_questions': 0},
      });
      expect(quiz.xpReward, 15);
    });

    test('handles direct format without quiz wrapper', () {
      final json = {
        'questions': [
          {
            'id': 1,
            'type': 'grammar',
            'question': 'Grammar Q?',
            'options': ['A', 'B', 'C', 'D'],
            'correct_index': 3,
            'explanation': '',
          },
        ],
        'total_questions': 1,
        'xp_reward': 15,
      };

      final quiz = NewsQuiz.fromJson(json);
      expect(quiz.questions.length, 1);
      expect(quiz.totalQuestions, 1);
    });

    test('handles empty questions list', () {
      final quiz = NewsQuiz.fromJson({
        'quiz': {'questions': [], 'total_questions': 0, 'xp_reward': 15},
      });
      expect(quiz.questions, isEmpty);
    });

    test('5-question quiz structure (placeholder format)', () {
      // Mimics what backend returns
      final json = {
        'quiz': {
          'questions': List.generate(
            5,
            (i) => {
              'id': i + 1,
              'type': i < 2
                  ? 'comprehension'
                  : (i < 4 ? 'vocabulary' : 'grammar'),
              'question': 'Question ${i + 1}?',
              'options': ['A', 'B', 'C', 'D'],
              'correct_index': i % 4,
              'explanation': 'Explanation ${i + 1}',
            },
          ),
          'total_questions': 5,
          'xp_reward': 15,
        },
      };

      final quiz = NewsQuiz.fromJson(json);

      expect(quiz.totalQuestions, 5);
      expect(quiz.xpReward, 15);
      expect(quiz.questions.length, 5);

      final types = quiz.questions.map((q) => q.type).toList();
      expect(types.where((t) => t == 'comprehension').length, 2);
      expect(types.where((t) => t == 'vocabulary').length, 2);
      expect(types.where((t) => t == 'grammar').length, 1);
    });
  });
}
