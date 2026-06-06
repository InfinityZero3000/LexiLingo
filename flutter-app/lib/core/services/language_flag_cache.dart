import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/l10n/app_localizations.dart';

class LanguageFlagCache {
  LanguageFlagCache._();

  static Future<void>? _preloadFuture;

  static List<String> get imageUrls => AppLocales.supportedLocales
      .map((locale) => AppLocales.flagPngUrlOf(locale.languageCode))
      .toList(growable: false);

  static Future<void> preload(BuildContext context) {
    return _preloadFuture ??= _preload(context);
  }

  static Future<void> _preload(BuildContext context) async {
    await Future.wait(
      imageUrls.map((imageUrl) async {
        try {
          await precacheImage(CachedNetworkImageProvider(imageUrl), context);
        } catch (_) {
          // Flags keep their per-widget fallback when the network is unavailable.
        }
      }),
    );
  }
}
