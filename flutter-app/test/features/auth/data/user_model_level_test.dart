import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/features/auth/data/models/user_model.dart';

Map<String, dynamic> _json([Map<String, dynamic> extra = const {}]) => {
  'id': 'u1',
  'email': 'a@b.c',
  'username': 'abc',
  'cefr_level': 'B2',
  'created_at': '2026-11-15T00:00:00Z',
  ...extra,
};

void main() {
  test('reads the certified level and the verified flag', () {
    final user = UserModel.fromJson(
      _json({'certified_level': 'B1', 'level_verified': false}),
    );
    expect(
      (user.cefrLevel, user.certifiedLevel, user.levelVerified),
      ('B2', 'B1', false),
    );
    expect(UserModel.fromJson(user.toJson()).certifiedLevel, 'B1');
  });

  test('an older backend without the fields reads as verified', () {
    final user = UserModel.fromJson(_json());
    expect((user.certifiedLevel, user.levelVerified), ('A1', true));
  });
}
