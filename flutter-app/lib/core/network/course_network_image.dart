import 'package:cached_network_image/cached_network_image.dart';
import 'package:cached_network_image_platform_interface/cached_network_image_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

/// One bucket for course thumbnails, bounded so it cannot grow without limit.
class CourseImageCache {
  CourseImageCache._();

  static final CacheManager instance = CacheManager(
    Config(
      'lexilingo_course_image_cache',
      stalePeriod: const Duration(days: 14),
      maxNrOfCacheObjects: 150,
    ),
  );

  /// Decode width shared by every course surface, so a thumbnail is decoded
  /// once and the list and Home reuse the same in-memory bitmap.
  static const int decodeWidth = 480;
}

/// Course thumbnail keyed by URL alone.
///
/// The key was once scoped per Hero to cure solid-black cards. That did not
/// cure it (black returned on web and was fixed by [ImageRenderMethodForWeb.
/// HttpGet]); it only made each section re-download, re-decode and re-store
/// the same file. Sharing one completer per URL is normal Flutter behaviour.
class CourseNetworkImage extends StatelessWidget {
  final String url;
  final Widget placeholder;
  final Widget Function() onError;
  final int? memCacheWidth;

  const CourseNetworkImage({
    super.key,
    required this.url,
    required this.placeholder,
    required this.onError,
    this.memCacheWidth = CourseImageCache.decodeWidth,
  });

  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      cacheManager: kIsWeb ? null : CourseImageCache.instance,
      imageRenderMethodForWeb: ImageRenderMethodForWeb.HttpGet,
      memCacheWidth: kIsWeb ? null : memCacheWidth,
      fit: BoxFit.cover,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      placeholderFadeInDuration: Duration.zero,
      placeholder: (_, __) => placeholder,
      errorWidget: (_, __, ___) => onError(),
    );
  }
}
