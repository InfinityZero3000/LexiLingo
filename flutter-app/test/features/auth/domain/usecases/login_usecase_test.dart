import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/login_usecase.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'login_usecase_test.mocks.dart';

@GenerateMocks([AuthRepository])
void main() {
  late LoginUseCase usecase;
  late MockAuthRepository mockAuthRepository;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    usecase = LoginUseCase(mockAuthRepository);
  });

  final testUser = UserEntity(
    id: 'test-id',
    email: 'test@example.com',
    username: 'testuser',
    displayName: 'Test User',
    provider: 'local',
    isVerified: true,
    level: 'B1',
    xp: 500,
    currentStreak: 7,
    createdAt: DateTime.parse('2026-01-20T10:00:00Z'),
    lastLogin: DateTime.parse('2026-01-24T10:00:00Z'),
  );

  final testParams = LoginParams(
    email: 'test@example.com',
    password: 'password123',
  );

  test('should login user successfully', () async {
    // Arrange
    when(mockAuthRepository.login(
      email: anyNamed('email'),
      password: anyNamed('password'),
    )).thenAnswer((_) async => Right(testUser));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result, Right(testUser));
    verify(mockAuthRepository.login(
      email: 'test@example.com',
      password: 'password123',
    ));
    verifyNoMoreInteractions(mockAuthRepository);
  });

  test('should return AuthFailure for invalid credentials', () async {
    // Arrange
    when(mockAuthRepository.login(
      email: anyNamed('email'),
      password: anyNamed('password'),
    )).thenAnswer((_) async => Left(AuthFailure('Invalid credentials')));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<AuthFailure>()),
      (_) => fail('Should return failure'),
    );
  });

  test('should return NetworkFailure when offline', () async {
    // Arrange
    when(mockAuthRepository.login(
      email: anyNamed('email'),
      password: anyNamed('password'),
    )).thenAnswer((_) async => Left(NetworkFailure()));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<NetworkFailure>()),
      (_) => fail('Should return failure'),
    );
  });

  test('should return RateLimitFailure when rate limited', () async {
    // Arrange
    when(mockAuthRepository.login(
      email: anyNamed('email'),
      password: anyNamed('password'),
    )).thenAnswer((_) async => Left(RateLimitFailure('Too many login attempts')));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<RateLimitFailure>()),
      (_) => fail('Should return failure'),
    );
  });
}
