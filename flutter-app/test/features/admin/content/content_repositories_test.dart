import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/state/paginated_list_controller.dart';
import 'package:lexilingo_app/features/admin/features/categories/data/categories_repository.dart';
import 'package:lexilingo_app/features/admin/features/content_lab/data/content_lab_repository.dart';
import 'package:lexilingo_app/features/admin/features/curriculum/data/curriculum_repository.dart';
import 'package:lexilingo_app/features/admin/features/grammar/data/grammar_repository.dart';
import 'package:lexilingo_app/features/admin/features/ielts/data/ielts_repository.dart';
import 'package:lexilingo_app/features/admin/features/topics/data/topics_repository.dart';
import 'package:lexilingo_app/features/admin/features/vocabulary/data/vocabulary_repository.dart';
import 'package:lexilingo_app/features/admin/shared/widgets/admin_paged_list.dart';

import 'fake_admin_api.dart';

void main() {
  const second = PageRequest(index: 1, size: 30);

  group('adminPage', () {
    Map<String, dynamic> parse(Map<String, dynamic> m) => m;

    test('reads a bare list, a keyed list and a paged body', () {
      expect(
        adminPage([
          {'a': 1},
        ], parse).items,
        hasLength(1),
      );
      expect(
        adminPage(
          {
            'courses': [
              {'a': 1},
              {'a': 2},
            ],
            'total': 40,
          },
          parse,
          keys: const ['courses'],
        ),
        isA<PageResult>()
            .having((p) => p.items.length, 'items', 2)
            .having((p) => p.total, 'total', 40),
      );
      expect(
        adminPage({
          'data': [
            {'a': 1},
          ],
          'pagination': {'total': 9},
        }, parse).total,
        9,
      );
    });

    test('skips rows that are not objects', () {
      expect(
        adminPage([
          'x',
          3,
          {'a': 1},
        ], parse).items,
        hasLength(1),
      );
    });

    test('an unknown body is an empty page', () {
      expect(adminPage('nope', parse).items, isEmpty);
    });
  });

  group('vocabulary', () {
    test(
      'lists with limit/offset and parses text or mapped translations',
      () async {
        final api = FakeAdminApi(
          (_) => (
            200,
            {
              'data': [
                {
                  'id': '1',
                  'word': 'cat',
                  'definition': 'an animal',
                  'translation': {'vi': 'con mèo'},
                  'part_of_speech': 'NOUN',
                  'difficulty_level': 'a1',
                },
                {
                  'id': '2',
                  'word': 'dog',
                  'definition': 'x',
                  'translation': 'chó',
                },
              ],
            },
          ),
        );
        final page = await VocabularyRepository(api: api.client).list(second);
        expect(api.requests.single.path, '/admin/vocabulary');
        expect(api.requests.single.queryParameters, {
          'offset': '30',
          'limit': '30',
        });
        expect(page.items.first.translation, 'con mèo');
        expect(page.items.first.partOfSpeech, 'noun');
        expect(page.items.first.level, 'A1');
        expect(page.items.last.translation, 'chó');
      },
    );

    test(
      'saves through the query string, the way the route takes it',
      () async {
        final api = FakeAdminApi((_) => (200, {'data': {}}));
        final repo = VocabularyRepository(api: api.client);
        await repo.save(
          word: 'a b',
          definition: 'd',
          translation: 't',
          partOfSpeech: 'verb',
          pronunciation: '',
          level: 'B1',
        );
        await repo.save(
          id: '7',
          word: 'w',
          definition: 'd',
          translation: 't',
          partOfSpeech: 'verb',
          pronunciation: 'p',
          level: 'B1',
        );
        expect(api.requests[0].method, 'POST');
        expect(api.requests[0].uri.queryParameters['word'], 'a b');
        expect(api.requests[1].method, 'PUT');
        expect(api.requests[1].uri.path, '/admin/vocabulary/7');
      },
    );
  });

  group('grammar', () {
    test('lists and writes JSON bodies', () async {
      final api = FakeAdminApi(
        (o) => o.method == 'GET'
            ? (
                200,
                {
                  'data': [
                    {
                      'id': '1',
                      'title': 'Past',
                      'level': 'a2',
                      'tags': ['x'],
                    },
                  ],
                },
              )
            : (200, {'data': {}}),
      );
      final repo = GrammarRepository(api: api.client);
      final page = await repo.list(second);
      expect(page.items.single.level, 'A2');
      expect(page.items.single.tags, ['x']);
      await repo.save(id: '1', data: {'title': 'T'});
      expect(api.requests.last.method, 'PUT');
      expect(api.requests.last.data, {'title': 'T'});
    });
  });

  group('content lab', () {
    test('pages questions and exams with limit/offset', () async {
      final api = FakeAdminApi(
        (_) => (
          200,
          {
            'data': [
              {'id': 'q', 'prompt': 'P', 'question_type': 'mcq'},
            ],
          },
        ),
      );
      final repo = ContentLabRepository(api: api.client);
      final page = await repo.listQuestions(second);
      expect(page.items.single.prompt, 'P');
      expect(api.requests.single.queryParameters['offset'], '30');
      await repo.listTestExams(second);
      expect(api.requests.last.path, '/admin/test-exams');
    });
  });

  group('curriculum', () {
    test('courses page by page/page_size and send only set filters', () async {
      final api = FakeAdminApi(
        (_) => (
          200,
          {
            'data': {
              'courses': [
                {'id': 'c', 'title': 'T', 'level': 'B1', 'is_published': true},
              ],
              'total': 21,
            },
          },
        ),
      );
      final page = await CurriculumRepository(api: api.client).listCourses(
        second,
        {'level': 'B1', 'is_published': false, 'search': null, 'x': ''},
      );
      expect(page.total, 21);
      expect(api.requests.single.queryParameters, {
        'page': '2',
        'page_size': '30',
        'level': 'B1',
        'is_published': false,
      });
    });

    test('units and lessons are one request each', () async {
      final api = FakeAdminApi(
        (o) => o.path == '/admin/units'
            ? (
                200,
                {
                  'data': {
                    'units': [
                      {'id': 'u', 'title': 'U', 'order_index': 0},
                    ],
                  },
                },
              )
            : (
                200,
                {
                  'data': [
                    {'id': 'l', 'title': 'L', 'total_exercises': 3},
                  ],
                },
              ),
      );
      final repo = CurriculumRepository(api: api.client);
      expect((await repo.listUnits('c')).items.single.title, 'U');
      expect(api.requests.last.queryParameters, {'course_id': 'c'});
      expect((await repo.listLessons('u')).items.single.totalExercises, 3);
      expect(api.requests.last.queryParameters, {'unit_id': 'u'});
    });
  });

  group('categories', () {
    test('lists inactive ones too and reports the list as one page', () async {
      final api = FakeAdminApi(
        (_) => (
          200,
          {
            'data': [
              {
                'id': '1',
                'name': 'Travel',
                'slug': 'travel',
                'is_active': false,
                'course_count': 4,
              },
            ],
          },
        ),
      );
      final page = await CategoriesRepository(api: api.client).list();
      expect(api.requests.single.queryParameters, {'active_only': false});
      expect(page.items.single.isActive, isFalse);
      expect(page.items.single.courseCount, 4);
      expect(page.total, 1);
    });
  });

  group('topics', () {
    test('reads the proxied {topics} list', () async {
      final api = FakeAdminApi(
        (_) => (
          200,
          {
            'data': {
              'topics': [
                {
                  'story_id': 's1',
                  'title': {'en': 'Airport', 'vi': 'Sân bay'},
                  'difficulty_level': 'A2',
                  'category': 'travel',
                  'estimated_minutes': 12,
                },
              ],
              'total': 1,
            },
          },
        ),
      );
      final page = await TopicsRepository(api: api.client).list();
      expect(api.requests.single.path, '/admin/ai-proxy/topics');
      expect(page.items.single.titleVi, 'Sân bay');
      expect(page.items.single.minutes, 12);
    });

    test(
      'saves with both titles, falling back to English for Vietnamese',
      () async {
        final api = FakeAdminApi((_) => (200, {'data': {}}));
        await TopicsRepository(api: api.client).save(
          titleEn: 'Hotel',
          titleVi: '',
          difficulty: 'B1',
          category: 'travel',
          minutes: 10,
          iconKey: 'travel',
          suggestedPrompts: const ['a'],
          tags: const [],
        );
        final body = api.requests.single.data as Map;
        expect(body['title'], {'en': 'Hotel', 'vi': 'Hotel'});
        expect(body.containsKey('story_id'), isFalse);
        expect(body['is_published'], true);
      },
    );
  });

  group('ielts', () {
    test('lists tests and attempts', () async {
      final api = FakeAdminApi(
        (o) => o.path.endsWith('/tests')
            ? (
                200,
                {
                  'data': [
                    {
                      'id': 't',
                      'title': 'Mock 1',
                      'test_type': 'academic',
                      'skill_scope': 'full',
                      'question_count': 40,
                    },
                  ],
                },
              )
            : (
                200,
                {
                  'data': [
                    {
                      'attempt_id': 'a',
                      'user_id': 'u',
                      'test_id': 't',
                      'status': 'submitted',
                      'overall_band': 6.5,
                      'started_at': '2026-01-02T03:04:05',
                    },
                  ],
                },
              ),
      );
      final repo = IeltsRepository(api: api.client);
      expect((await repo.listTests(second)).items.single.questionCount, 40);
      final attempts = await repo.listAttempts();
      expect(attempts.items.single.overallBand, 6.5);
      expect(attempts.items.single.startedAt, isNotNull);
      expect(api.requests.last.queryParameters, {'limit': 100});
    });

    test('validate posts and reads the verdict', () async {
      final api = FakeAdminApi(
        (_) => (
          200,
          {
            'data': {
              'publishable': false,
              'problems': ['no sections'],
              'counts': {'reading': 12, 'productive_parts': 2},
            },
          },
        ),
      );
      final result = await IeltsRepository(api: api.client).validate('t');
      expect(api.requests.single.method, 'POST');
      expect(api.requests.single.path, '/admin/ielts/tests/t/validate');
      expect(result.publishable, isFalse);
      expect(result.problems, ['no sections']);
      expect(result.counts['reading'], 12);
    });
  });
}
