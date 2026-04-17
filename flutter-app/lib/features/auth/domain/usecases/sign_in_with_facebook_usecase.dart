import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class SignInWithFacebookUseCase
    implements UseCase<UserEntity, SignInWithFacebookParams> {
  final AuthRepository repository;

  SignInWithFacebookUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(
    SignInWithFacebookParams params,
  ) async {
    return await repository.loginWithFacebook(params.idToken);
  }
}

class SignInWithFacebookParams {
  final String idToken;

  const SignInWithFacebookParams({required this.idToken});
}
