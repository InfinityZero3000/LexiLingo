import 'package:lexilingo_app/core/usecase/usecase.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class SignOutUseCase implements UseCase<void, NoParams> {
  final AuthRepository repository;

  SignOutUseCase(this.repository);

  @override
  Future<void> call(NoParams params) async {
    return await repository.signOut();
  }
}
