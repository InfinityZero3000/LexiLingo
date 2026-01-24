import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Register new user use case
class RegisterUseCase implements UseCase<UserEntity, RegisterParams> {
  final AuthRepository repository;

  RegisterUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(RegisterParams params) async {
    return await repository.register(
      email: params.email,
      username: params.username,
      password: params.password,
      displayName: params.displayName,
    );
  }
}

class RegisterParams {
  final String email;
  final String username;
  final String password;
  final String? displayName;

  RegisterParams({
    required this.email,
    required this.username,
    required this.password,
    this.displayName,
  });
}
