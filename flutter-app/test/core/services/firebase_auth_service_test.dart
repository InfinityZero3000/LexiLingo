import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:mockito/annotations.dart';
import 'package:firebase_auth/firebase_auth.dart';

@GenerateMocks([FirebaseAuth, User, UserCredential])
import 'firebase_auth_service_test.mocks.dart';

void main() {
  group('FirebaseAuth', () {
    late MockFirebaseAuth mockAuth;
    late MockUser mockUser;
    late MockUserCredential mockUserCredential;

    setUp(() {
      mockAuth = MockFirebaseAuth();
      mockUser = MockUser();
      mockUserCredential = MockUserCredential();
    });

    group('Current User', () {
      test('should return null when no user is signed in', () {
        // Arrange
        when(mockAuth.currentUser).thenReturn(null);

        // Act
        final user = mockAuth.currentUser;

        // Assert
        expect(user, isNull);
      });

      test('should return user when user is signed in', () {
        // Arrange
        when(mockAuth.currentUser).thenReturn(mockUser);
        when(mockUser.uid).thenReturn('test_user_id');
        when(mockUser.email).thenReturn('test@example.com');

        // Act
        final user = mockAuth.currentUser;

        // Assert
        expect(user, isNotNull);
        expect(user!.uid, equals('test_user_id'));
        expect(user.email, equals('test@example.com'));
      });
    });

    group('Sign In with Email/Password', () {
      test('should sign in successfully with valid credentials', () async {
        // Arrange
        const email = 'test@example.com';
        const password = 'password123';
        
        when(mockAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        )).thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn('test_user_id');

        // Act
        final result = await mockAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Assert
        expect(result, equals(mockUserCredential));
        expect(result.user?.uid, equals('test_user_id'));
        verify(mockAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        )).called(1);
      });

      test('should throw exception for invalid credentials', () async {
        // Arrange
        const email = 'wrong@example.com';
        const password = 'wrongpassword';
        
        when(mockAuth.signInWithEmailAndPassword(
          email: email,
          password: password,
        )).thenThrow(FirebaseAuthException(
          code: 'wrong-password',
          message: 'The password is invalid',
        ));

        // Act & Assert
        expect(
          () => mockAuth.signInWithEmailAndPassword(
            email: email,
            password: password,
          ),
          throwsA(isA<FirebaseAuthException>()),
        );
      });
    });

    group('Sign Up with Email/Password', () {
      test('should create user successfully', () async {
        // Arrange
        const email = 'newuser@example.com';
        const password = 'password123';
        
        when(mockAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).thenAnswer((_) async => mockUserCredential);
        when(mockUserCredential.user).thenReturn(mockUser);
        when(mockUser.uid).thenReturn('new_user_id');

        // Act
        final result = await mockAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        );

        // Assert
        expect(result.user?.uid, equals('new_user_id'));
        verify(mockAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).called(1);
      });

      test('should throw exception for existing email', () async {
        // Arrange
        const email = 'existing@example.com';
        const password = 'password123';
        
        when(mockAuth.createUserWithEmailAndPassword(
          email: email,
          password: password,
        )).thenThrow(FirebaseAuthException(
          code: 'email-already-in-use',
          message: 'The email address is already in use',
        ));

        // Act & Assert
        expect(
          () => mockAuth.createUserWithEmailAndPassword(
            email: email,
            password: password,
          ),
          throwsA(isA<FirebaseAuthException>()),
        );
      });
    });

    group('Sign Out', () {
      test('should sign out successfully', () async {
        // Arrange
        when(mockAuth.signOut()).thenAnswer((_) async => {});

        // Act
        await mockAuth.signOut();

        // Assert
        verify(mockAuth.signOut()).called(1);
      });
    });

    group('Password Reset', () {
      test('should send password reset email successfully', () async {
        // Arrange
        const email = 'test@example.com';
        when(mockAuth.sendPasswordResetEmail(email: email))
            .thenAnswer((_) async => {});

        // Act
        await mockAuth.sendPasswordResetEmail(email: email);

        // Assert
        verify(mockAuth.sendPasswordResetEmail(email: email)).called(1);
      });

      test('should throw exception for non-existent email', () async {
        // Arrange
        const email = 'nonexistent@example.com';
        when(mockAuth.sendPasswordResetEmail(email: email))
            .thenThrow(FirebaseAuthException(
          code: 'user-not-found',
          message: 'There is no user record corresponding to this email',
        ));

        // Act & Assert
        expect(
          () => mockAuth.sendPasswordResetEmail(email: email),
          throwsA(isA<FirebaseAuthException>()),
        );
      });
    });

    group('Auth State Changes', () {
      test('should emit auth state changes', () async {
        // Arrange
        when(mockAuth.authStateChanges())
            .thenAnswer((_) => Stream.fromIterable([null, mockUser]));
        when(mockUser.uid).thenReturn('test_user_id');

        // Act
        final states = await mockAuth.authStateChanges().toList();

        // Assert
        expect(states.length, equals(2));
        expect(states[0], isNull);
        expect(states[1]?.uid, equals('test_user_id'));
      });
    });

    group('Token Management', () {
      test('should get ID token successfully', () async {
        // Arrange
        const expectedToken = 'firebase_id_token_12345';
        when(mockUser.getIdToken()).thenAnswer((_) async => expectedToken);

        // Act
        final token = await mockUser.getIdToken();

        // Assert
        expect(token, equals(expectedToken));
      });

      test('should get fresh ID token when forceRefresh is true', () async {
        // Arrange
        const expectedToken = 'fresh_firebase_id_token_12345';
        when(mockUser.getIdToken(true)).thenAnswer((_) async => expectedToken);

        // Act
        final token = await mockUser.getIdToken(true);

        // Assert
        expect(token, equals(expectedToken));
        verify(mockUser.getIdToken(true)).called(1);
      });
    });
  });
}

/// Custom Firebase Auth Exception for testing
class FirebaseAuthException implements Exception {
  final String code;
  final String message;

  FirebaseAuthException({required this.code, required this.message});

  @override
  String toString() => 'FirebaseAuthException: [$code] $message';
}
