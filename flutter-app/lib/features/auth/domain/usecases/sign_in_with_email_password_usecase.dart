import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class SignInWithEmailPasswordParams {
  final String email;
  final String password;

  SignInWithEmailPasswordParams({
    required this.email,
    required this.password,
  });
}

class SignInWithEmailPasswordUseCase 
    implements UseCase<UserEntity, SignInWithEmailPasswordParams> {
  final AuthRepository repository;

  SignInWithEmailPasswordUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(SignInWithEmailPasswordParams params) async {
    return await repository.login(
      email: params.email,
      password: params.password,
    );
  }
}
