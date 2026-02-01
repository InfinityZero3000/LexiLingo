import 'package:dartz/dartz.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import '../entities/settings.dart';
import '../repositories/settings_repository.dart';

class GetSettingsUseCase {
  final SettingsRepository repository;

  GetSettingsUseCase({required this.repository});

  Future<Either<Failure, Settings>> call(String userId) async {
    return await repository.getSettings(userId);
  }
}
