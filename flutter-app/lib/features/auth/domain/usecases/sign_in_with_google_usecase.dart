import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class SignInWithGoogleUseCase implements UseCase<UserEntity, SignInWithGoogleParams> {
  final AuthRepository repository;

  SignInWithGoogleUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(SignInWithGoogleParams params) async {
    return await repository.loginWithGoogle(params.idToken);
  }
}

class SignInWithGoogleParams {
  final String idToken;

  const SignInWithGoogleParams({required this.idToken});
}
