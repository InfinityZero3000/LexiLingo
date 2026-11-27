import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/services/facebook_sign_in_service.dart';

const _facebook = OAuthCredential(
  providerId: 'facebook.com',
  signInMethod: 'facebook.com',
  accessToken: 'fb-access-token',
);

class _User extends Fake implements User {
  _User(this.log, this.email, {this.token = 'token', this.linkError});

  final List<String> log;
  @override
  final String? email;
  final String token;
  final String? linkError;

  @override
  Future<UserCredential> linkWithCredential(AuthCredential credential) async {
    log.add('link ${credential.providerId} to $email');
    if (linkError != null) throw FirebaseAuthException(code: linkError!);
    return _Credential(this);
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => token;
}

class _Credential extends Fake implements UserCredential {
  _Credential(this.user);

  @override
  final User? user;
}

class _Auth extends Fake implements FirebaseAuth {
  _Auth({required this.googleEmail, this.linkError, this.popupError});

  final String googleEmail;
  final String? linkError;
  final String? popupError;
  final log = <String>[];

  @override
  Future<UserCredential> signInWithPopup(AuthProvider provider) async {
    log.add('popup ${provider.providerId}');
    if (popupError != null) throw FirebaseAuthException(code: popupError!);
    return _Credential(_User(log, googleEmail, linkError: linkError));
  }

  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    log.add('sign in ${credential.providerId}');
    return _Credential(_User(log, googleEmail, token: 'facebook-id-token'));
  }

  @override
  Future<void> signOut() async => log.add('sign out');
}

const _request = FacebookLinkRequired('owner@example.com', _facebook);

void main() {
  test('recognises the backend refusal for an existing account', () {
    expect(
      FacebookSignInService.isExistingAccountRefusal(
        'Email already registered. Please login with your existing method.',
      ),
      isTrue,
    );
    expect(
      FacebookSignInService.isExistingAccountRefusal(
        'User account is inactive',
      ),
      isFalse,
    );
  });

  group('linkRequest', () {
    FirebaseAuthException error({
      String code = 'account-exists-with-different-credential',
      String? email = 'owner@example.com',
      AuthCredential? credential = _facebook,
    }) =>
        FirebaseAuthException(code: code, email: email, credential: credential);

    test('keeps what is needed to link', () {
      final request = FacebookSignInService.linkRequest(error(), isWeb: true);

      expect(request?.email, 'owner@example.com');
      expect(request?.credential, _facebook);
    });

    test('offers nothing it cannot finish', () {
      for (final candidate in [
        error(code: 'network-request-failed'),
        error(email: null),
        error(credential: null),
      ]) {
        expect(
          FacebookSignInService.linkRequest(candidate, isWeb: true),
          isNull,
        );
      }
      expect(FacebookSignInService.linkRequest(error(), isWeb: false), isNull);
    });
  });

  group('linkWithGoogle', () {
    test('links after Google proves the same email, then signs in with '
        'Facebook', () async {
      final auth = _Auth(googleEmail: 'Owner@Example.com');

      final token = await FacebookSignInService(
        auth: auth,
      ).linkWithGoogle(_request);

      expect(token, 'facebook-id-token');
      expect(auth.log, [
        'popup google.com',
        'link facebook.com to Owner@Example.com',
        'sign in facebook.com',
        'sign out',
      ]);
    });

    test('never links to a different Google account', () async {
      final auth = _Auth(googleEmail: 'someone-else@example.com');

      await expectLater(
        FacebookSignInService(auth: auth).linkWithGoogle(_request),
        throwsA(
          predicate(
            (e) => '$e'.contains(FacebookSignInService.emailMismatchCode),
          ),
        ),
      );
      expect(auth.log, ['popup google.com', 'sign out']);
    });

    test('an already linked account still signs in', () async {
      final auth = _Auth(
        googleEmail: 'owner@example.com',
        linkError: 'provider-already-linked',
      );

      expect(
        await FacebookSignInService(auth: auth).linkWithGoogle(_request),
        'facebook-id-token',
      );
    });

    test('closing the Google popup cancels quietly', () async {
      final auth = _Auth(
        googleEmail: 'owner@example.com',
        popupError: 'popup-closed-by-user',
      );

      expect(
        await FacebookSignInService(auth: auth).linkWithGoogle(_request),
        isNull,
      );
      expect(auth.log, ['popup google.com', 'sign out']);
    });

    test('a failed link signs nobody in', () async {
      final auth = _Auth(
        googleEmail: 'owner@example.com',
        linkError: 'credential-already-in-use',
      );

      await expectLater(
        FacebookSignInService(auth: auth).linkWithGoogle(_request),
        throwsException,
      );
      expect(auth.log, isNot(contains('sign in facebook.com')));
      expect(auth.log.last, 'sign out');
    });
  });
}
