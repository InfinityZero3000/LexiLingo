import 'package:dartz/dartz.dart';
import '../../../../core/error/failures.dart';
import '../../../../core/usecase/usecase.dart';
import '../entities/user_entity.dart';
import '../repositories/auth_repository.dart';

/// Login with Google OAuth use case
class LoginWithGoogleUseCase implements UseCase<UserEntity, GoogleLoginParams> {
  final AuthRepository repository;

  LoginWithGoogleUseCase(this.repository);

  @override
  Future<Either<Failure, UserEntity>> call(GoogleLoginParams params) async {
    return await repository.loginWithGoogle(params.idToken);
  }
}

class GoogleLoginParams {
  final String idToken;

  GoogleLoginParams({required this.idToken});
}
