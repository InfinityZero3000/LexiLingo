import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/navigation/reload_app.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import 'package:lexilingo_app/core/widgets/error_widget.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

typedef DeferredLibraryLoader = Future<void> Function();

/// Loads a `deferred as` library, then builds the page that lives in it.
///
/// On the web each deferred library is its own JS chunk, fetched here on first
/// use; elsewhere `loadLibrary` completes at once. A failed fetch shows a retry.
/// Chunk names are not content-hashed, so a tab opened before a deploy can
/// never load the new chunks: after a second failure on the web the page
/// offers a full reload, which is the only thing that fixes that.
class DeferredPage extends StatefulWidget {
  const DeferredPage({
    super.key,
    required this.loadLibrary,
    required this.builder,
    this.offerReload = kIsWeb,
    this.onReload = reloadApp,
  });

  final DeferredLibraryLoader loadLibrary;
  final WidgetBuilder builder;
  final bool offerReload;
  final VoidCallback onReload;

  @override
  State<DeferredPage> createState() => _DeferredPageState();
}

class _DeferredPageState extends State<DeferredPage> {
  bool _loaded = false;
  bool _failed = false;
  int _failures = 0;

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
      setState(() {
        _failed = true;
        _failures++;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loaded) return widget.builder(context);
    final reload = widget.offerReload && _failures >= 2;
    return Scaffold(
      appBar: AppBar(leading: const AppBackButton()),
      body: SafeArea(
        child: !_failed
            ? const SkeletonList()
            : reload
            ? Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ErrorDisplayWidget.fromMessage(
                    message: 'errors.networkRetry'.tr(),
                    compact: true,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                    ),
                    onPressed: widget.onReload,
                    child: Text('home.reload'.tr()),
                  ),
                ],
              )
            : ErrorDisplayWidget.fromMessage(
                message: 'errors.networkRetry'.tr(),
                onRetry: _load,
              ),
      ),
    );
  }
}
