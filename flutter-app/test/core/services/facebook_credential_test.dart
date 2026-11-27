import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_facebook_auth/flutter_facebook_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';

void main() {
  test(
    'a limited-login token goes to Firebase as an ID token with the nonce',
    () {
      final credential =
          FacebookSignInService.firebaseCredential(
                LimitedToken(
                  userId: '1',
                  userName: 'n',
                  userEmail: null,
                  nonce: 'hashed',
                  tokenString: 'jwt',
                ),
                'raw',
              )
              as OAuthCredential;

      expect(credential.providerId, 'facebook.com');
      expect(credential.idToken, 'jwt');
      expect(credential.rawNonce, 'raw');
      expect(credential.accessToken, isNull);
    },
  );

  test('a classic token goes to Firebase as an access token', () {
    final credential =
        FacebookSignInService.firebaseCredential(
              ClassicToken(
                userId: '1',
                tokenString: 'access',
                applicationId: 'app',
                expires: DateTime(2030),
                grantedPermissions: null,
                declinedPermissions: null,
              ),
              'raw',
            )
            as OAuthCredential;

    expect(credential.accessToken, 'access');
    expect(credential.idToken, isNull);
  });
}
