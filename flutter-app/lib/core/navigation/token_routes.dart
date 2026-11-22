import 'package:flutter/material.dart';

/// Resolves a route name that carries a query, like `/verify-email?token=…`, against the
/// app's own routes table, passing the query parameters as the route arguments.
///
/// Deep links open routes with `pushNamed('/reset-password?token=…')`. A routes table only
/// matches the exact name, so without this the push failed with "could not find a generator
/// for route" and the mailed link never reached its page.
Route<dynamic>? queryRoute(
  RouteSettings settings,
  Map<String, WidgetBuilder> routes,
) {
  final uri = Uri.tryParse(settings.name ?? '');
  if (uri == null || !uri.hasQuery) return null;
  final builder = routes[uri.path];
  if (builder == null) return null;
  return MaterialPageRoute<void>(
    settings: RouteSettings(
      name: uri.path,
      arguments: Map<String, dynamic>.from(uri.queryParameters),
    ),
    builder: builder,
  );
}
