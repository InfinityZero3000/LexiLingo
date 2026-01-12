import 'package:lexilingo_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:lexilingo_app/features/auth/domain/entities/user_entity.dart';
import 'package:lexilingo_app/features/auth/domain/repositories/auth_repository.dart';

class AuthRepositoryImpl implements AuthRepository {
  final AuthRemoteDataSource remoteDataSource;

  AuthRepositoryImpl({required this.remoteDataSource});

  @override
  Future<UserEntity?> getCurrentUser() => remoteDataSource.getCurrentUser();

  @override
  Future<UserEntity?> signInWithGoogle() => remoteDataSource.signIn();

  @override
  Future<UserEntity?> signInWithEmailPassword(String email, String password) =>
      remoteDataSource.signInWithEmailPassword(email, password);

  @override
  Future<void> signOut() => remoteDataSource.signOut();

  @override
  Stream<UserEntity?> get authStateChanges => remoteDataSource.authStateChanges;
}
