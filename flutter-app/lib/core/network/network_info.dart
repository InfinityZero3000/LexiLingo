import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

abstract class NetworkInfo {
  Future<bool> get isConnected;
}

/// Connectivity-based implementation with DNS ping fallback (skips ping on web).
class NetworkInfoImpl implements NetworkInfo {
  final Connectivity connectivity;
  final Duration dnsCheckTimeout;
  final List<String> probeHosts;

  NetworkInfoImpl({
    Connectivity? connectivity,
    this.dnsCheckTimeout = const Duration(seconds: 2),
    this.probeHosts = const ['google.com', 'cloudflare.com'],
  }) : connectivity = connectivity ?? Connectivity();

  @override
  Future<bool> get isConnected async {
    final status = await connectivity.checkConnectivity();
    if (status == ConnectivityResult.none) return false;
    if (kIsWeb) return true; // skip DNS ping on web

    for (final host in probeHosts) {
      try {
        final lookup = await InternetAddress.lookup(host).timeout(dnsCheckTimeout);
        if (lookup.isNotEmpty) return true;
      } catch (_) {
        // try next host
      }
    }
    return false;
  }
}
