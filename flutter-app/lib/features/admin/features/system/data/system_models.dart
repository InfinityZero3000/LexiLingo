/// Models for the read-only system views. Ops, monitoring and AI-quality
/// bodies are raw dicts whose fields grow over time, so they are read through
/// [JsonSnapshot] instead of one class per field.
library;

String formatNumber(num value) {
  if (value >= 1000000) return '${(value / 1000000).toStringAsFixed(1)}M';
  if (value >= 1000) return '${(value / 1000).toStringAsFixed(1)}K';
  return value == value.truncate()
      ? value.toInt().toString()
      : value.toStringAsFixed(1);
}

String humanizeKey(String key) {
  final spaced = key.replaceAll('_', ' ').replaceAll('.', ' · ');
  return spaced.isEmpty ? key : spaced[0].toUpperCase() + spaced.substring(1);
}

class JsonSnapshot {
  JsonSnapshot(this.raw);

  factory JsonSnapshot.from(dynamic body) {
    if (body is Map) return JsonSnapshot(Map<String, dynamic>.from(body));
    if (body is List) return JsonSnapshot({'items': body});
    return JsonSnapshot(const {});
  }

  final Map<String, dynamic> raw;

  bool get isEmpty => scalars.isEmpty && tables.isEmpty;

  /// Numbers, booleans and short strings, nested maps flattened to two levels.
  late final List<MapEntry<String, String>> scalars = _flatten(raw, '', 0);

  /// Lists of maps, by key.
  late final Map<String, List<Map<String, dynamic>>> tables = {
    for (final e in raw.entries)
      if (e.value is List && (e.value as List).any((x) => x is Map))
        e.key: [
          for (final x in e.value as List)
            if (x is Map) Map<String, dynamic>.from(x),
        ],
  };

  static List<MapEntry<String, String>> _flatten(
    Map<String, dynamic> map,
    String prefix,
    int depth,
  ) {
    final out = <MapEntry<String, String>>[];
    for (final e in map.entries) {
      final key = prefix.isEmpty ? e.key : '$prefix.${e.key}';
      final v = e.value;
      if (v is num) {
        out.add(MapEntry(humanizeKey(key), formatNumber(v)));
      } else if (v is bool) {
        out.add(MapEntry(humanizeKey(key), v ? '✓' : '✗'));
      } else if (v is String && v.isNotEmpty && v.length <= 80) {
        out.add(MapEntry(humanizeKey(key), v));
      } else if (v is Map && depth < 1) {
        out.addAll(_flatten(Map<String, dynamic>.from(v), key, depth + 1));
      } else if (v is List && !v.any((x) => x is Map) && v.isNotEmpty) {
        out.add(MapEntry(humanizeKey(key), v.take(6).join(', ')));
      }
    }
    return out;
  }

  static String rowTitle(Map<String, dynamic> row) {
    for (final k in const ['name', 'title', 'slug', 'id', 'task', 'event']) {
      final v = row[k];
      if (v != null && '$v'.isNotEmpty) return '$v';
    }
    return row.values.isEmpty ? '' : '${row.values.first}';
  }

  static String rowCaption(Map<String, dynamic> row) {
    final parts = <String>[];
    for (final e in row.entries) {
      final v = e.value;
      if (v is num || v is bool || (v is String && v.length <= 40)) {
        parts.add('${humanizeKey(e.key)}: ${v is num ? formatNumber(v) : v}');
      }
      if (parts.length == 4) break;
    }
    return parts.join(' · ');
  }
}

class FunnelStep {
  const FunnelStep({
    required this.key,
    required this.label,
    required this.count,
    this.pctOfFirst,
    this.pctOfPrevious,
  });

  factory FunnelStep.fromJson(Map<String, dynamic> j) => FunnelStep(
    key: '${j['key'] ?? ''}',
    label: '${j['label'] ?? j['key'] ?? ''}',
    count: (j['count'] as num?)?.toInt() ?? 0,
    pctOfFirst: (j['pct_of_first'] as num?)?.toDouble(),
    pctOfPrevious: (j['pct_of_previous'] as num?)?.toDouble(),
  );

  final String key;
  final String label;
  final int count;
  final double? pctOfFirst;
  final double? pctOfPrevious;
}

List<FunnelStep> parseFunnelSteps(dynamic body) {
  final map = body is Map ? body : const {};
  final steps = map['steps'];
  if (steps is! List) return const [];
  return [
    for (final s in steps)
      if (s is Map) FunnelStep.fromJson(Map<String, dynamic>.from(s)),
  ];
}

class CoursePopularity {
  const CoursePopularity({
    required this.title,
    required this.enrollments,
    this.completions,
  });

  factory CoursePopularity.fromJson(Map<String, dynamic> j) => CoursePopularity(
    title: '${j['course_title'] ?? j['title'] ?? ''}',
    enrollments: (j['enrollments'] as num?)?.toInt() ?? 0,
    completions: (j['completions'] as num?)?.toInt(),
  );

  final String title;
  final int enrollments;
  final int? completions;
}

class RoleSummary {
  const RoleSummary({
    required this.slug,
    required this.name,
    this.description,
    this.level,
    this.isSystem = false,
  });

  factory RoleSummary.fromJson(Map<String, dynamic> j) => RoleSummary(
    slug: '${j['slug'] ?? ''}',
    name: '${j['name'] ?? j['slug'] ?? ''}',
    description: j['description'] as String?,
    level: (j['level'] as num?)?.toInt(),
    isSystem: j['is_system'] == true,
  );

  final String slug;
  final String name;
  final String? description;
  final int? level;
  final bool isSystem;
}

/// Permission slugs (`resource:action`) of one role, grouped by resource.
class RolePermissions {
  const RolePermissions(this.byResource);

  factory RolePermissions.fromJson(dynamic body) {
    final map = body is Map ? body : const {};
    final out = <String, List<String>>{};
    final perms = map['permissions'];
    if (perms is List) {
      for (final p in perms) {
        if (p is! Map) continue;
        final resource = '${p['resource'] ?? ''}';
        final action = '${p['action'] ?? ''}';
        if (resource.isEmpty) continue;
        (out[resource] ??= []).add(action);
      }
    }
    return RolePermissions(out);
  }

  final Map<String, List<String>> byResource;
}
