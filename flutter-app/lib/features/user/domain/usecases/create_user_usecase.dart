import '../entities/user.dart';
import '../repositories/user_repository.dart';

class CreateUserUseCase {
  final UserRepository repository;

  CreateUserUseCase({required this.repository});

  Future<void> call(User user) async {
    await repository.createUser(user);
  }
}
