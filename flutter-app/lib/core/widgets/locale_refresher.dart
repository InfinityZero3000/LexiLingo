import 'package:flutter/material.dart';

/// Rebuilds the whole subtree once a locale change has finished loading.
///
/// easy_localization's `.tr()` reads a static table that is only swapped when
/// the Localizations delegates finish loading, a frame or more after
/// `setLocale`. Widgets that rebuild earlier read the old table, and widgets
/// that never subscribed (const or stateful screens) are not rebuilt at all, so
/// part of the UI stayed in the previous language. `Localizations.localeOf`
/// notifies only after that load completes, so refreshing from here is correct.
class LocaleRefresher extends StatefulWidget {
  const LocaleRefresher({super.key, required this.child});

  final Widget child;

  @override
  State<LocaleRefresher> createState() => _LocaleRefresherState();
}

class _LocaleRefresherState extends State<LocaleRefresher> {
  Locale? _locale;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final locale = Localizations.localeOf(context);
    final changed = _locale != null && _locale != locale;
    _locale = locale;
    if (changed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _rebuildAll(context as Element);
      });
    }
  }

  static void _rebuildAll(Element root) {
    void rebuild(Element element) {
      element.markNeedsBuild();
      element.visitChildren(rebuild);
    }

    root.visitChildren(rebuild);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
