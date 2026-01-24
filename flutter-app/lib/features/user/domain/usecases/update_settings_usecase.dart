import '../entities/settings.dart';
import '../repositories/settings_repository.dart';

class UpdateSettingsUseCase {
  final SettingsRepository repository;

  UpdateSettingsUseCase({required this.repository});

  Future<void> call(Settings settings) async {
    await repository.updateSettings(settings);
  }
}
