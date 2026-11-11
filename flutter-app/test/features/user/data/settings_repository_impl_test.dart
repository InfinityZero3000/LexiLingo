import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lexilingo_app/core/error/failures.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/user/data/datasources/settings_local_data_source.dart';
import 'package:lexilingo_app/features/user/data/datasources/settings_remote_data_source.dart';
import 'package:lexilingo_app/features/user/data/models/settings_model.dart';
import 'package:lexilingo_app/features/user/data/repositories/settings_repository_impl.dart';
import 'package:lexilingo_app/features/user/domain/entities/settings.dart';

class _Local implements SettingsLocalDataSource {
  _Local(this.stored);

  SettingsModel? stored;
  int writes = 0;

  @override
  Future<SettingsModel?> getSettings(String userId) async => stored;

  @override
  Future<int> updateSettings(SettingsModel settings) async {
    writes += 1;
    stored = settings;
    return 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FailingRemote extends SettingsRemoteDataSource {
  _FailingRemote() : super(apiClient: ApiClient(enableLogging: false));

  @override
  Future<SettingsModel> updateReminderPreferences(Settings settings) async {
    throw Exception('offline');
  }
}

SettingsModel _stored() => const SettingsModel(id: 1, userId: 'u1');

void main() {
  test('a reminder change the server rejects is not saved locally', () async {
    final local = _Local(_stored());
    final repo = SettingsRepositoryImpl(
      localDataSource: local,
      remoteDataSource: _FailingRemote(),
    );

    final result = await repo.updateSettings(
      _stored().copyWith(emailReminderEnabled: true),
    );

    expect(result.isLeft(), isTrue);
    expect(local.writes, 0);
    expect(local.stored?.emailReminderEnabled, isFalse);
  });

  test(
    'a non-reminder change still saves locally when the server is unreachable',
    () async {
      final local = _Local(_stored());
      final repo = SettingsRepositoryImpl(
        localDataSource: local,
        remoteDataSource: _FailingRemote(),
      );

      final result = await repo.updateSettings(
        _stored().copyWith(soundEnabled: false),
      );

      expect(result, const Right<Failure, void>(null));
      expect(local.writes, 1);
    },
  );
}
