import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/l10n/ui_text.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/view_state.dart';

typedef DeferredLibraryLoader = Future<void> Function();

/// Loads a `deferred as` library, then builds the page that lives in it.
///
/// On the web each deferred library is its own JS chunk, fetched here on first
/// use; elsewhere `loadLibrary` completes at once. A failed fetch shows a retry.
class DeferredPage extends StatefulWidget {
  const DeferredPage({
    super.key,
    required this.loadLibrary,
    required this.builder,
  });

  final DeferredLibraryLoader loadLibrary;
  final WidgetBuilder builder;

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  bool _loaded = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (_failed) setState(() => _failed = false);
    try {
      await widget.loadLibrary();
      if (!mounted) return;
      setState(() => _loaded = true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded) return widget.builder(context);
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton()),
      body: SafeArea(
        child: ViewStateBody(
          isLoading: !_failed,
          hasData: false,
          error: _failed ? const UiText.key('errors.networkRetry') : null,
          onRetry: _load,
          builder: (_) => const SizedBox.shrink(),
        ),
      ),
    );
  }
}
