library;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';
import 'package:lexilingo_app/core/utils/avatar_utils.dart';

class NetworkAvatarImage extends StatelessWidget {
  const NetworkAvatarImage({
    super.key,
    required this.imageUrl,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
  });

  final String? imageUrl;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final resolved = AvatarUtils.normalizeAvatarUrl(imageUrl);
    final fallbackWidget =
        fallback ??
        Container(
          color: AppColors.primary.withValues(alpha: 0.2),
          child: const Icon(Icons.person, color: AppColors.primary),
        );

    if (resolved == null) {
      return fallbackWidget;
    }

    if (AvatarUtils.isSvgUrl(resolved)) {
      return SvgPicture.network(
        resolved,
        fit: fit,
        width: width,
        height: height,
        placeholderBuilder: (_) => const Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }

    return Image.network(
      resolved,
      fit: fit,
      width: width,
      height: height,
      errorBuilder: (_, __, ___) => fallbackWidget,
    );
  }
}