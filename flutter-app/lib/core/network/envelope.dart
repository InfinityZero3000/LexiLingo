/// Reads the several response shapes the admin and learner APIs use.
library;

const _envelopeKeys = {
  'data',
  'meta',
  'success',
  'message',
  'error',
  'pagination',
};

/// `{data, meta}` and `{success, data}` give back `data`; anything else,
/// including a raw list or a map that merely has a `data` field, is returned
/// as it came.
dynamic unwrapEnvelope(dynamic body) {
  if (body is! Map) return body;
  if (!body.containsKey('data')) return body;
  final onlyEnvelopeKeys = body.keys.every(_envelopeKeys.contains);
  return onlyEnvelopeKeys ? body['data'] : body;
}

class PageBody {
  const PageBody(this.items, this.total);

  final List<dynamic> items;
  final int? total;
}

/// A list body in any of its shapes: a raw list, `{data: [...], pagination}`,
/// `{items, total}` or `{results, count}`.
PageBody extractPage(dynamic body) {
  if (body is List) return PageBody(body, null);
  if (body is! Map) return const PageBody([], null);

  List<dynamic>? items;
  for (final key in const ['data', 'items', 'results']) {
    final value = body[key];
    if (value is List) {
      items = value;
      break;
    }
  }
  final pagination = body['pagination'];
  final total =
      _asInt(pagination is Map ? pagination['total'] : null) ??
      _asInt(body['total']) ??
      _asInt(body['count']);
  return PageBody(items ?? const [], total);
}

int? _asInt(Object? value) => value is num ? value.toInt() : null;
