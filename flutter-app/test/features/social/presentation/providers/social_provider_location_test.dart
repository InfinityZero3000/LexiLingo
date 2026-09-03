import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:lexilingo_app/core/network/api_client.dart';
import 'package:lexilingo_app/features/social/data/datasources/social_remote_datasource.dart';
import 'package:lexilingo_app/features/social/data/repositories/social_repository.dart';
import 'package:lexilingo_app/features/social/domain/entities/social_entities.dart';
import 'package:lexilingo_app/features/social/presentation/providers/social_provider.dart';

void main() {
  late GeolocatorPlatform originalPlatform;
  late _FakeGeolocatorPlatform geolocator;

  setUp(() {
    originalPlatform = GeolocatorPlatform.instance;
    geolocator = _FakeGeolocatorPlatform();
    GeolocatorPlatform.instance = geolocator;
  });

  tearDown(() => GeolocatorPlatform.instance = originalPlatform);

  test('syncs location when web permission cannot be determined', () async {
    final remote = _RecordingSocialRemoteDataSource();
    final provider = SocialProvider(
      repository: SocialRepository(remote: remote),
    );

    await provider.loadNearbyUsers();

    expect(geolocator.requestPermissionCalls, 0);
    expect(remote.updatedLatitude, 10.75);
    expect(remote.updatedLongitude, 106.67);
    expect(provider.nearbyError, isNull);
  });
}

class _FakeGeolocatorPlatform extends GeolocatorPlatform {
  int requestPermissionCalls = 0;

  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.unableToDetermine;

  @override
  Future<LocationPermission> requestPermission() async {
    requestPermissionCalls++;
    return LocationPermission.denied;
  }

  @override
  Future<bool> isLocationServiceEnabled() async => true;

  @override
  Future<Position> getCurrentPosition({
    LocationSettings? locationSettings,
  }) async {
    return Position(
      latitude: 10.75,
      longitude: 106.67,
      timestamp: DateTime(2026),
      accuracy: 5,
      altitude: 0,
      altitudeAccuracy: 0,
      heading: 0,
      headingAccuracy: 0,
      speed: 0,
      speedAccuracy: 0,
    );
  }
}

class _RecordingSocialRemoteDataSource extends SocialRemoteDataSource {
  _RecordingSocialRemoteDataSource() : super(apiClient: ApiClient());

  double? updatedLatitude;
  double? updatedLongitude;

  @override
  Future<void> updateLocation({
    required bool enabled,
    double? latitude,
    double? longitude,
    double? accuracyMeters,
  }) async {
    updatedLatitude = latitude;
    updatedLongitude = longitude;
  }

  @override
  Future<({List<UserSocialProfileEntity> users, bool locationEnabled})>
  getNearbyUsers({int limit = 10, double radiusKm = 25}) async {
    return (users: <UserSocialProfileEntity>[], locationEnabled: true);
  }
}
