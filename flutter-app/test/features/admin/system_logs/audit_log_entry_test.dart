import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/admin/features/system_logs/data/logs_repository.dart';

void main() {
  group('AuditLogEntry.fromJson', () {
    test('parses audit log fields and stringifies identifiers', () {
      final entry = AuditLogEntry.fromJson({
        'created_at': '2026-08-06T08:30:00Z',
        'action': 'assign_role',
        'resource_type': 'user',
        'resource_id': 42,
        'details': 'Assigned admin role',
        'user_id': 7,
      });

      expect(entry.createdAt, '2026-08-06T08:30:00Z');
      expect(entry.action, 'assign_role');
      expect(entry.resourceType, 'user');
      expect(entry.resourceId, '42');
      expect(entry.details, 'Assigned admin role');
      expect(entry.userId, '7');
    });

    test('uses empty required fields and preserves nullable fields', () {
      final entry = AuditLogEntry.fromJson({
        'created_at': null,
        'action': null,
        'resource_type': null,
        'resource_id': null,
        'details': null,
        'user_id': null,
      });

      expect(entry.createdAt, isEmpty);
      expect(entry.action, isEmpty);
      expect(entry.resourceType, isEmpty);
      expect(entry.resourceId, isNull);
      expect(entry.details, isNull);
      expect(entry.userId, isNull);
    });
  });
}
