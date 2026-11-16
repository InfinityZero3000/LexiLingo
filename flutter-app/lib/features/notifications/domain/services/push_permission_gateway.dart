enum PushPermission { notDetermined, granted, denied, unsupported }

abstract class PushPermissionGateway {
  Future<PushPermission> status();
  Future<PushPermission> requestPermission();
}
