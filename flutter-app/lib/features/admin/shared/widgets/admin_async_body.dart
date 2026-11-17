import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';

import 'admin_error_view.dart';

/// Loads once, then shows skeleton, [AdminErrorView] (403 and 503 included),
/// the empty state or the data, with pull-to-refresh over the data.
class AdminAsyncBody<T> extends StatefulWidget {
  const AdminAsyncBody({
    super.key,
    required this.load,
    required this.builder,
    this.isEmpty,
    this.empty,
  });

  final Future<T> Function() load;
  final Widget Function(BuildContext context, T data) builder;
  final bool Function(T data)? isEmpty;
  final Widget? empty;

  @override
  State<AdminAsyncBody<T>> createState() => AdminAsyncBodyState<T>();
}

class AdminAsyncBodyState<T> extends State<AdminAsyncBody<T>> {
  T? _data;
  Object? _error;
  bool _loading = true;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    reload();
  }

  Future<void> reload() async {
    final generation = ++_generation;
    if (_data == null) setState(() => _loading = true);
    try {
      final data = await widget.load();
      if (!mounted || generation != _generation) return;
      setState(() {
        _data = data;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    if (data == null) {
      if (_loading) {
        return const Padding(
          padding: EdgeInsets.all(AppSpacing.lg),
          child: SkeletonList(),
        );
      }
      return AdminErrorView(error: _error ?? 'unknown', onRetry: reload);
    }
    if (widget.isEmpty?.call(data) ?? false) {
      return widget.empty ?? const SizedBox.shrink();
    }
    return RefreshIndicator(
      onRefresh: reload,
      child: widget.builder(context, data),
    );
  }
}
