import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
}

/// Connectivity-based implementation with DNS ping fallback.
///
/// On web it never blocks: connectivity_plus can only read
/// `navigator.onLine` there, which stays false for a while after a VPN/WARP
/// toggle, a network switch or a sleep/wake even though requests go through.
/// Trusting it failed every call before it was sent, and only a page reload
/// cleared it. A real outage fails the request itself, and `ApiClient`
/// already retries that once.
class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;
  final Duration dnsCheckTimeout;
  final List<String> probeHosts;
  final bool _isWeb;

  NetworkInfoImpl({
    Connectivity? connectivity,
    this.dnsCheckTimeout = const Duration(seconds: 2),
    this.probeHosts = const ['google.com', 'cloudflare.com'],
    bool? isWeb,
  }) : connectivity = connectivity ?? Connectivity(),
       _isWeb = isWeb ?? kIsWeb;

  @override
  Future<bool> get isConnected async {
    if (_isWeb) return true;

    final statuses = await connectivity.checkConnectivity();
    if (statuses.every((s) => s == ConnectivityResult.none)) return false;

    for (final host in probeHosts) {
      try {
        final lookup = await InternetAddress.lookup(
          host,
        ).timeout(dnsCheckTimeout);
        if (lookup.isNotEmpty) return true;
      } catch (_) {
        // try next host
      }
    }
    return false;
  }
}
