import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';

import '../../../../shared/widgets/admin_shell.dart';
import '../../data/system_models.dart';

/// A titled surface holding one idea, per the card spec.
class SystemSection extends StatelessWidget {
  const SystemSection({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: AppRadius.lgAll,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleSmall),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}

class KeyValueRow extends StatelessWidget {
  const KeyValueRow({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 5,
            child: Text(
              label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            flex: 6,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

/// Every scalar of a [JsonSnapshot] as label/value rows.
class SnapshotRows extends StatelessWidget {
  const SnapshotRows({super.key, required this.snapshot, this.limit = 40});

  final JsonSnapshot snapshot;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final entries = snapshot.scalars.take(limit).toList();
    return Column(
      children: [
        for (final e in entries) KeyValueRow(label: e.key, value: e.value),
      ],
    );
  }
}

/// Table-like list of maps: first column as title, the rest as a caption.
class SnapshotTable extends StatelessWidget {
  const SnapshotTable({super.key, required this.rows, this.limit = 20});

  final List<Map<String, dynamic>> rows;
  final int limit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = rows.take(limit).toList();
    return Column(
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    JsonSnapshot.rowTitle(shown[i]),
                    style: theme.textTheme.bodyMedium,
                  ),
                  Text(
                    JsonSnapshot.rowCaption(shown[i]),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
        if (rows.length > limit)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: Text(
              '+${rows.length - limit}',
              style: theme.textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}

/// Horizontal bars scaled to the largest value; token-coloured, no chart lib.
class BarList extends StatelessWidget {
  const BarList({super.key, required this.items, this.suffix = ''});

  final List<BarItem> items;
  final String suffix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final max = items.fold<double>(0, (m, i) => i.value > m ? i.value : m);
    return Column(
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Text(
                      '${formatNumber(item.value)}$suffix',
                      style: theme.textTheme.labelMedium,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                ClipRRect(
                  borderRadius: AppRadius.smAll,
                  child: LinearProgressIndicator(
                    value: max <= 0 ? 0 : item.value / max,
                    minHeight: 8,
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class BarItem {
  const BarItem(this.label, this.value);
  final String label;
  final double value;
}

/// Metric tiles in a responsive wrap: two per row on phones, more when wide.
class MetricWrap extends StatelessWidget {
  const MetricWrap({super.key, required this.metrics});

  final List<MetricTile> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final columns = c.maxWidth >= 900 ? 4 : (c.maxWidth >= 560 ? 3 : 2);
        final width = (c.maxWidth - AppSpacing.md * (columns - 1)) / columns;
        return Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final m in metrics)
              SizedBox(
                width: width,
                child: StatCard(label: m.label, value: m.value, note: m.note),
              ),
          ],
        );
      },
    );
  }
}

class MetricTile {
  const MetricTile(this.label, this.value, {this.note});
  final String label;
  final String value;
  final String? note;
}

/// Page padding shared by the system screens.
const systemPagePadding = EdgeInsets.fromLTRB(
  AppSpacing.lg,
  AppSpacing.md,
  AppSpacing.lg,
  AppSpacing.xxl,
);

/// App bar with the drawer button on phones, over a scrollable body.
class SystemPage extends StatelessWidget {
  const SystemPage({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.bottom,
  });

  final String title;
  final Widget body;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= adminWideBreakpoint;
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: wide
            ? null
            : IconButton(
                tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
                icon: const Icon(Icons.menu_rounded),
                onPressed: AdminShell.openDrawer,
              ),
        title: Text(title),
        actions: actions,
        bottom: bottom,
      ),
      body: body,
    );
  }
}

/// A whole [JsonSnapshot]: its scalars as one card, each list as another.
class SnapshotView extends StatelessWidget {
  const SnapshotView({super.key, required this.snapshot, this.title});

  final JsonSnapshot snapshot;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: systemPagePadding,
      children: [
        if (snapshot.scalars.isNotEmpty)
          SystemSection(
            title: title ?? '',
            child: SnapshotRows(snapshot: snapshot),
          ),
        for (final e in snapshot.tables.entries) ...[
          const SizedBox(height: AppSpacing.md),
          SystemSection(
            title: humanizeKey(e.key),
            child: SnapshotTable(rows: e.value),
          ),
        ],
      ],
    );
  }
}
