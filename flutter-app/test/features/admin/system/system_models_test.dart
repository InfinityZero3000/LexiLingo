import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/system/data/system_models.dart';
import 'package:lexilingo_app/features/admin/features/system/data/system_repository.dart';
import 'package:lexilingo_app/features/admin/features/system_logs/data/logs_repository.dart';

void main() {
  group('JsonSnapshot', () {
    test('flattens scalars two levels deep and skips long strings', () {
      final s = JsonSnapshot.from({
        'status': 'ok',
        'uptime_seconds': 12500,
        'cpu': {'percent': 41.5, 'cores': 4},
        'deep': {
          'a': {'b': 1},
        },
        'flag': true,
        'blob': 'x' * 200,
        'tags': ['a', 'b'],
      });
      final map = {for (final e in s.scalars) e.key: e.value};
      expect(map['Status'], 'ok');
      expect(map['Uptime seconds'], '12.5K');
      expect(map['Cpu · percent'], '41.5');
      expect(map['Flag'], '✓');
      expect(map['Tags'], 'a, b');
      expect(map.containsKey('Blob'), isFalse);
      expect(map.keys.any((k) => k.contains('deep')), isFalse);
    });

    test('lists of maps become tables; a raw list becomes `items`', () {
      final s = JsonSnapshot.from([
        {'name': 'redis', 'status': 'up'},
      ]);
      expect(s.tables['items'], hasLength(1));
      expect(JsonSnapshot.rowTitle(s.tables['items']!.first), 'redis');
      expect(
        JsonSnapshot.rowCaption(s.tables['items']!.first),
        contains('Status: up'),
      );
      expect(JsonSnapshot.from(null).isEmpty, isTrue);
    });
  });

  test('activation funnel steps parse counts and percentages', () {
    final steps = parseFunnelSteps({
      'steps': [
        {
          'key': 'signed_up',
          'label': 'Signed up',
          'count': 100,
          'pct_of_first': 100.0,
        },
        {
          'key': 'verified',
          'count': 60,
          'pct_of_first': 60.0,
          'pct_of_previous': 60,
        },
      ],
    });
    expect(steps.map((s) => s.count), [100, 60]);
    expect(steps[1].label, 'verified');
    expect(steps[1].pctOfPrevious, 60);
    expect(parseFunnelSteps('nope'), isEmpty);
  });

  test('role permissions group actions by resource', () {
    final p = RolePermissions.fromJson({
      'permissions': [
        {'resource': 'users', 'action': 'read'},
        {'resource': 'users', 'action': 'update'},
        {'resource': 'courses', 'action': 'read'},
      ],
    });
    expect(p.byResource['users'], ['read', 'update']);
    expect(p.byResource.keys, containsAll(['users', 'courses']));
  });

  test('extractList reads every list shape the admin API uses', () {
    expect(
      extractList([
        {'a': 1},
      ]),
      hasLength(1),
    );
    expect(
      extractList({
        'data': [
          {'a': 1},
        ],
      }),
      hasLength(1),
    );
    expect(
      extractList({
        'data': {
          'users': [
            {'a': 1},
            {'b': 2},
          ],
        },
      }),
      hasLength(2),
    );
    expect(
      extractList({
        'items': [
          {'a': 1},
        ],
      }),
      hasLength(1),
    );
    expect(extractList('x'), isEmpty);
  });

  test('audit facets tolerate missing keys', () {
    final f = AuditFacets.fromJson({
      'actions': ['login', 'delete'],
    });
    expect(f.actions, ['login', 'delete']);
    expect(f.resourceTypes, isEmpty);
    expect(AuditFacets.fromJson(null).actions, isEmpty);
  });

  test('CoursePopularity reads title and counts', () {
    final c = CoursePopularity.fromJson({
      'course_title': 'IELTS',
      'enrollments': 12,
      'completions': 3,
    });
    expect((c.title, c.enrollments, c.completions), ('IELTS', 12, 3));
  });
}
