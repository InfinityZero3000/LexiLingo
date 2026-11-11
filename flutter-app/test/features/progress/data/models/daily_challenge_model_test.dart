import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/progress/data/models/daily_challenge_model.dart';
import 'package:lexilingo_app/features/progress/domain/entities/daily_challenge_entity.dart';

void main() {
  test('challenges list accepts an Entity-typed orElse (games hub crash)', () {
    final response = DailyChallengesResponseModel.fromJson({
      'challenges': [
        {'id': 'a', 'title': 'A', 'is_completed': true},
      ],
    });

    final DailyChallengeEntity picked = response.challenges.firstWhere(
      (c) => !c.isCompleted,
      orElse: () => response.challenges.first,
    );

    expect(picked.id, 'a');
  });
}
