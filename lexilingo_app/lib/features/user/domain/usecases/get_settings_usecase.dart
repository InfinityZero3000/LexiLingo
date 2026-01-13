import '../entities/settings.dart';
import '../repositories/settings_repository.dart';

class GetSettingsUseCase {
  final SettingsRepository repository;

  GetSettingsUseCase({required this.repository});

  Future<Settings?> call(String userId) async {
    return await repository.getSettings(userId);
  }
}
