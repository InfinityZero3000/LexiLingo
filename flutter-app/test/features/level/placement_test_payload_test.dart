import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/level/data/datasources/proficiency_data_source.dart';

void main() {
  group('buildPlacementAnswerPayload', () {
    test(
      'converts answer map into backend list contract sorted by question id',
      () {
        final payload = buildPlacementAnswerPayload({'10': 2, '2': 0, '1': 3});

        expect(payload, [
          {'question_id': 1, 'selected_option': 3},
          {'question_id': 2, 'selected_option': 0},
          {'question_id': 10, 'selected_option': 2},
        ]);
      },
    );

    test('skips non-numeric question ids', () {
      final payload = buildPlacementAnswerPayload({'intro': 1, '3': 2});

      expect(payload, [
        {'question_id': 3, 'selected_option': 2},
      ]);
    });
  });
}
