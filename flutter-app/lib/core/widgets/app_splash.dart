import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/widgets/lottie_loading_widget.dart';

/// Full-bleed start-up screen for the apps (the web keeps the light spinner,
/// so its first paint never waits on an image): portrait artwork on tall viewports, landscape
/// on wide ones. Both keep the mascot centred, so `cover` crops only sky.
class AppSplash extends StatelessWidget {
  const AppSplash({super.key});

  static const mobileAsset = 'assets/loading/loading-mobile.jpg';
  static const desktopAsset = 'assets/loading/loading-pc.jpg';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return LoadingScreen(message: 'common.loading'.tr());
    return LayoutBuilder(
      builder: (context, constraints) {
        final portrait = constraints.maxHeight >= constraints.maxWidth;
        return SizedBox.expand(
          child: Image.asset(
            portrait ? mobileAsset : desktopAsset,
            fit: BoxFit.cover,
            alignment: Alignment.center,
            gaplessPlayback: true,
            excludeFromSemantics: true,
            errorBuilder: (_, _, _) =>
                const ColoredBox(color: Color(0xFF4FC3F7)),
          ),
        );
      },
    );
  }
}
