import '../entities/user.dart';
import '../repositories/user_repository.dart';

class GetUserUseCase {
  final UserRepository repository;

  GetUserUseCase({required this.repository});

  Future<User?> call(String userId) async {
    return await repository.getUser(userId);
  }
}
