import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/services/background_sync_queue_service.dart';
import 'package:lexilingo_app/core/services/local_cache_service.dart';
import 'package:lexilingo_app/core/services/user_scope_service.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

class OfflineSyncCenterPage extends StatefulWidget {
  const OfflineSyncCenterPage({super.key});

  @override
  State<OfflineSyncCenterPage> createState() => _OfflineSyncCenterPageState();
}

class _OfflineSyncCenterPageState extends State<OfflineSyncCenterPage> {
  final Connectivity _connectivity = Connectivity();
  final LocalCacheService _cacheService = LocalCacheService.instance;
  final BackgroundSyncQueueService _queueService =
      BackgroundSyncQueueService.instance;

  OfflineSyncSnapshot? _snapshot;
  String? _errorMessage;
  bool _isLoading = true;
  bool _isMutating = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadSnapshot();
    });
  }

  Future<void> _loadSnapshot() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final connectivityResults = await _connectivity.checkConnectivity();
      final isOnline = connectivityResults.any(
        (result) => result != ConnectivityResult.none,
      );
      final cacheSize = await _cacheService.getCacheSize();
      final cacheCountsByType = await _cacheService.getCacheCountsByType();
      final userScope = await UserScopeService.getActiveUserId();
      final queueSummary = userScope == null || userScope.isEmpty
          ? SyncQueueSummary.unsupported
          : await _queueService.getSummary(userScope: userScope);

      if (!mounted) return;
      setState(() {
        _snapshot = OfflineSyncSnapshot(
          isOnline: isOnline,
          cacheSize: cacheSize,
          cacheCountsByType: cacheCountsByType,
          activeUserScope: userScope,
          queueSummary: queueSummary,
        );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _clearExpiredCache() async {
    setState(() => _isMutating = true);
    try {
      final cleared = await _cacheService.clearExpired();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'offlineSync.expiredCleared'.tr(namedArgs: {'count': '$cleared'}),
          ),
        ),
      );
      await _loadSnapshot();
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  Future<void> _confirmClearAllCache() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('offlineSync.clearAllTitle'.tr()),
          content: Text('offlineSync.clearAllMessage'.tr()),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text('common.cancel'.tr()),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text('offlineSync.clearAllConfirm'.tr()),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _isMutating = true);
    try {
      await _cacheService.clearAll();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('offlineSync.allCacheCleared'.tr())),
      );
      await _loadSnapshot();
    } finally {
      if (mounted) setState(() => _isMutating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? AppColors.backgroundDark
          : AppColors.backgroundLight,
      appBar: AppBar(
        title: Text('offlineSync.title'.tr()),
        actions: [
          IconButton(
            tooltip: 'common.refresh'.tr(),
            onPressed: _isLoading || _isMutating ? null : _loadSnapshot,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: _isLoading && _snapshot == null
            ? const Center(child: CircularProgressIndicator())
            : _errorMessage != null && _snapshot == null
            ? _ErrorState(message: _errorMessage!, onRetry: _loadSnapshot)
            : RefreshIndicator(
                onRefresh: _loadSnapshot,
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  children: [
                    _ConnectionCard(snapshot: _snapshot!),
                    const SizedBox(height: 14),
                    _CacheCard(
                      snapshot: _snapshot!,
                      isMutating: _isMutating,
                      onClearExpired: _clearExpiredCache,
                      onClearAll: _confirmClearAllCache,
                    ),
                    const SizedBox(height: 14),
                    _QueueCard(snapshot: _snapshot!),
                  ],
                ),
              ),
      ),
    );
  }
}

class OfflineSyncSnapshot {
  const OfflineSyncSnapshot({
    required this.isOnline,
    required this.cacheSize,
    required this.cacheCountsByType,
    required this.activeUserScope,
    required this.queueSummary,
  });

  final bool isOnline;
  final int cacheSize;
  final Map<String, int> cacheCountsByType;
  final String? activeUserScope;
  final SyncQueueSummary queueSummary;

  bool get hasActiveUser =>
      activeUserScope != null && activeUserScope!.isNotEmpty;
}

class _ConnectionCard extends StatelessWidget {
  const _ConnectionCard({required this.snapshot});

  final OfflineSyncSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = snapshot.isOnline
        ? AppColors.greenSuccess
        : AppColors.warning;

    return _Panel(
      child: Row(
        children: [
          _IconBadge(
            icon: snapshot.isOnline
                ? Icons.wifi_rounded
                : Icons.wifi_off_rounded,
            color: color,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  snapshot.isOnline
                      ? 'offlineSync.onlineTitle'.tr()
                      : 'offlineSync.offlineTitle'.tr(),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  snapshot.isOnline
                      ? 'offlineSync.onlineSubtitle'.tr()
                      : 'offlineSync.offlineSubtitle'.tr(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppColorRoles.textSecondary(isDark),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CacheCard extends StatelessWidget {
  const _CacheCard({
    required this.snapshot,
    required this.isMutating,
    required this.onClearExpired,
    required this.onClearAll,
  });

  final OfflineSyncSnapshot snapshot;
  final bool isMutating;
  final VoidCallback onClearExpired;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final entries = snapshot.cacheCountsByType.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.storage_rounded,
            color: AppColorRoles.primary(isDark),
            title: 'offlineSync.cacheTitle'.tr(),
            subtitle: 'offlineSync.cacheSubtitle'.tr(),
          ),
          const SizedBox(height: 14),
          _MetricRow(
            label: 'offlineSync.totalEntries'.tr(),
            value: '${snapshot.cacheSize}',
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            _EmptyLine(text: 'offlineSync.noCache'.tr())
          else
            for (final entry in entries)
              _MetricRow(
                label: _cacheTypeLabel(entry.key),
                value: '${entry.value}',
              ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: isMutating ? null : onClearExpired,
                  icon: const Icon(Icons.cleaning_services_rounded),
                  label: Text('offlineSync.clearExpired'.tr()),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: isMutating ? null : onClearAll,
                  icon: isMutating
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_sweep_rounded),
                  label: Text('offlineSync.clearAll'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _cacheTypeLabel(String type) {
    final key = 'offlineSync.cacheTypes.$type';
    final translated = key.tr();
    return translated == key ? type : translated;
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.snapshot});

  final OfflineSyncSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final summary = snapshot.queueSummary;

    return _Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _PanelTitle(
            icon: Icons.sync_rounded,
            color: AppColors.teal,
            title: 'offlineSync.queueTitle'.tr(),
            subtitle: 'offlineSync.queueSubtitle'.tr(),
          ),
          const SizedBox(height: 14),
          if (!snapshot.hasActiveUser)
            _EmptyLine(text: 'offlineSync.noUserScope'.tr())
          else if (!summary.persistentQueueAvailable)
            _EmptyLine(text: 'offlineSync.queueUnavailable'.tr())
          else ...[
            _MetricRow(
              label: 'offlineSync.totalQueued'.tr(),
              value: '${summary.totalCount}',
            ),
            _MetricRow(
              label: 'offlineSync.readyQueued'.tr(),
              value: '${summary.readyCount}',
            ),
            _MetricRow(
              label: 'offlineSync.scheduledQueued'.tr(),
              value: '${summary.scheduledCount}',
            ),
            _MetricRow(
              label: 'offlineSync.retryingQueued'.tr(),
              value: '${summary.retryingCount}',
            ),
          ],
          const SizedBox(height: 10),
          Text(
            'offlineSync.queueHint'.tr(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AppColorRoles.textSecondary(isDark),
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDarkMuted : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? AppColors.borderDarkSoft : AppColors.slate200,
        ),
      ),
      child: child,
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        _IconBadge(icon: icon, color: color),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: AppColorRoles.textSecondary(isDark),
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _IconBadge extends StatelessWidget {
  const _IconBadge({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Icon(icon, color: color, size: 23),
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
              ),
            ),
          ),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _EmptyLine extends StatelessWidget {
  const _EmptyLine({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Text(
      text,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
        color: AppColorRoles.textSecondary(isDark),
        height: 1.35,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline_rounded,
              color: Theme.of(context).colorScheme.error,
              size: 42,
            ),
            const SizedBox(height: 12),
            Text(
              'offlineSync.loadFailed'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppColorRoles.textSecondary(isDark),
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text('common.retry'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
