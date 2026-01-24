import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class GetCurrentUserUseCase implements UseCase<UserEntity?, NoParams> {
  final AuthRepository repository;

  GetCurrentUserUseCase(this.repository);

  @override
  Future<UserEntity?> call(NoParams params) async {
    return await repository.getCurrentUser();
  }
}
