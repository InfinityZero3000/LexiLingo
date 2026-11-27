import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/network/response_models.dart';
import 'package:lexilingo_app/features/user/presentation/pages/settings_page.dart';

/// The refusal as the backend's global error handler sends it.
ApiErrorException _refusal(Map<String, dynamic>? details) => ApiErrorException(
  ErrorResponseEnvelope.fromJson({
    'error': {
      'code': 'AUTH_FORBIDDEN',
      'message':
          'For your security, sign in again before deleting your account.',
      'details': details,
    },
    'meta': {'request_id': 'r1', 'timestamp': '2026-11-27T00:00:00Z'},
  }),
);

void main() {
  test('asks the learner to sign in again only for that refusal', () {
    expect(
      needsRecentSignIn(_refusal({'reason': 'recent_sign_in_required'})),
      true,
    );
    expect(needsRecentSignIn(_refusal({'reason': 'something_else'})), false);
    expect(needsRecentSignIn(_refusal(null)), false);
    expect(needsRecentSignIn(Exception('offline')), false);
  });
}
