import 'dart:convert';
import 'dart:ui' show Locale;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// On Flutter Web, fetches i18n JSON files via HTTP with a cache-busting
/// `?_=<timestamp>` query parameter.
///
/// Flutter's service worker only strips `?v=` from URLs before looking up its
/// cache. Any other query parameter (e.g. `?_=`) is NOT stripped, so the URL
/// does NOT match a RESOURCES entry and the SW passes the request straight to
/// the network. This guarantees that every app launch gets the latest
/// translation files from Vercel, completely bypassing the SW cache.
///
/// On mobile/desktop, the standard [rootBundle] is used (no network overhead).
class NetworkFirstAssetLoader extends AssetLoader {
  final String _cb = DateTime.now().millisecondsSinceEpoch.toString();

  @override
  Future<Map<String, dynamic>?> load(String path, Locale locale) async {
    final langCode = locale.toStringWithSeparator(separator: '_');

    if (kIsWeb) {
      try {
        // /assets/ prefix is Flutter web's public URL prefix for asset paths.
        final url = '/assets/$path/$langCode.json?_=$_cb';
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        // fall through to rootBundle
      }
    }

    final data = await rootBundle.loadString('$path/$langCode.json');
    return json.decode(data) as Map<String, dynamic>;
  }
}
