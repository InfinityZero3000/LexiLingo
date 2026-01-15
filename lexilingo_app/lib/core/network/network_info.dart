abstract class NetworkInfo {
  Future<bool> get isConnected;
}

/// Simple implementation that always returns true for web
/// Can be enhanced later with connectivity_plus package
class NetworkInfoImpl implements NetworkInfo {
  @override
  Future<bool> get isConnected async => true;
}
