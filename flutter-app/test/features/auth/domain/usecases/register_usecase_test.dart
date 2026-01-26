import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:lexilingo_app/features/auth/domain/usecases/register_usecase.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';

import 'register_usecase_test.mocks.dart';

@GenerateMocks([AuthRepository])
void main() {
  late RegisterUseCase usecase;
  late MockAuthRepository mockAuthRepository;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    usecase = RegisterUseCase(mockAuthRepository);
  });

  final testUser = UserEntity(
    id: 'test-id',
    email: 'test@example.com',
    username: 'testuser',
    displayName: 'Test User',
    provider: 'local',
    isVerified: false,
    level: 'A1',
    xp: 0,
    currentStreak: 0,
    createdAt: DateTime.parse('2026-01-24T10:00:00Z'),
  );

  final testParams = RegisterParams(
    email: 'test@example.com',
    username: 'testuser',
    password: 'password123',
    displayName: 'Test User',
  );

  test('should register user successfully', () async {
    // Arrange
    when(mockAuthRepository.register(
      email: anyNamed('email'),
      username: anyNamed('username'),
      password: anyNamed('password'),
      displayName: anyNamed('displayName'),
    )).thenAnswer((_) async => Right(testUser));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result, Right(testUser));
    verify(mockAuthRepository.register(
      email: 'test@example.com',
      username: 'testuser',
      password: 'password123',
      displayName: 'Test User',
    ));
    verifyNoMoreInteractions(mockAuthRepository);
  });

  test('should return ConflictFailure when email already exists', () async {
    // Arrange
    when(mockAuthRepository.register(
      email: anyNamed('email'),
      username: anyNamed('username'),
      password: anyNamed('password'),
      displayName: anyNamed('displayName'),
    )).thenAnswer((_) async => Left(ConflictFailure('Email already registered')));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<ConflictFailure>()),
      (_) => fail('Should return failure'),
    );
  });

  test('should return ValidationFailure for invalid input', () async {
    // Arrange
    when(mockAuthRepository.register(
      email: anyNamed('email'),
      username: anyNamed('username'),
      password: anyNamed('password'),
      displayName: anyNamed('displayName'),
    )).thenAnswer((_) async => Left(ValidationFailure('Invalid email format')));

    // Act
    final result = await usecase(testParams);

    // Assert
    expect(result.isLeft(), true);
    result.fold(
      (failure) => expect(failure, isA<ValidationFailure>()),
      (_) => fail('Should return failure'),
    );
  });

  test('should return NetworkFailure when no internet connection', () async {
    // Arrange
    when(mockAuthRepository.register(
      email: anyNamed('email'),
      username: anyNamed('username'),
      password: anyNamed('password'),
      displayName: anyNamed('displayName'),
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
}
