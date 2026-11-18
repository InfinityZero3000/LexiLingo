import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';

import '../../../core/constants/api_endpoints.dart';
import 'package:lexilingo_app/features/admin/core/theme/admin_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';
import 'package:lexilingo_app/core/widgets/skeleton_loading.dart';
import 'package:lexilingo_app/core/widgets/stat_card.dart';
import '../../auth/presentation/auth_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class SuperDashboardScreen extends StatefulWidget {
  const SuperDashboardScreen({super.key});

  @override
  State<SuperDashboardScreen> createState() => _SuperDashboardScreenState();
}

class _SuperDashboardScreenState extends State<SuperDashboardScreen> {
  Map<String, dynamic>? _system;
  Map<String, dynamic>? _services;
  Map<String, dynamic>? _info;
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final responses = await Future.wait([
      _getOrNull(ApiEndpoints.monitoringSystem),
      _getOrNull(ApiEndpoints.monitoringServices),
      _getOrNull(ApiEndpoints.systemInfo),
    ]);
    if (!mounted) return;
    final infoResponse = responses[2];
    setState(() {
      _system = responses[0] ?? _system;
      _services = responses[1] ?? _services;
      _info = infoResponse == null
          ? _info
          : (infoResponse['data'] ?? infoResponse) as Map<String, dynamic>?;
      _error = responses.any((response) => response == null)
          ? 'One or more services are unavailable.'
          : null;
      _loading = false;
    });
  }

  Future<Map<String, dynamic>?> _getOrNull(String path) async {
    try {
      return await ApiClient.instance.get(path);
    } catch (_) {
      return null;
    }
  }

  String _percent(String key) {
    final value = key == 'cpu'
        ? (_system?['cpu_percent'] as num?)
        : ((_system?[key] as Map?)?['percent'] as num?);
    return value == null ? '--' : '${value.toStringAsFixed(0)}%';
  }

  @override
  Widget build(BuildContext context) {
    if (!context.watch<AuthProvider>().isSuperAdmin) {
      return _restricted(context);
    }
    final totals = _info?['totals'] as Map?;
    return Scaffold(
      backgroundColor: context.ac.background,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.menu_rounded),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text(
          'adminUi.superDash.superAdminDashboard'.tr(),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        actions: [
          IconButton(
            tooltip: 'adminUi.superDash.refresh'.tr(),
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Padding(
              padding: EdgeInsets.all(20),
              child: Column(
                children: [
                  SkeletonBox(height: 120, borderRadius: 16),
                  SizedBox(height: AppSpacing.md),
                  SkeletonBox(height: 220, borderRadius: 16),
                ],
              ),
            )
          : _error != null && _system == null
          ? _DashboardError(message: _error!, onRetry: _load)
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                children: [
                  Text(
                    'adminUi.superDash.systemOversight'.tr(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: context.ac.primary,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    'adminUi.superDash.atAGlancePlatformStatus'.tr(),
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: context.ac.onSurface,
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      'adminUi.superDash.someDashboardDataCouldNot'.tr(),
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: context.ac.error),
                    ),
                  ],
                  const SizedBox(height: 18),
                  GridView.count(
                    crossAxisCount: 2,
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                    children: [
                      StatCard(
                        label: 'adminUi.superDash.users'.tr(),
                        value: totals?['users']?.toString() ?? '--',
                        icon: Icons.people_outline,
                      ),
                      StatCard(
                        label: 'adminUi.superDash.courses'.tr(),
                        value: totals?['courses']?.toString() ?? '--',
                        icon: Icons.school_outlined,
                      ),
                      StatCard(
                        label: 'adminUi.superDash.cpuMemory'.tr(),
                        value: '${_percent('cpu')} / ${_percent('memory')}',
                        icon: Icons.memory_outlined,
                      ),
                      StatCard(
                        label: 'adminUi.superDash.diskUsage'.tr(),
                        value: _percent('disk'),
                        icon: Icons.storage_outlined,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  _panel('Service Status', [
                    _ServiceRow(
                      label: 'adminUi.superDash.backendApi'.tr(),
                      status: 'healthy',
                    ),
                    _ServiceRow(
                      label: 'PostgreSQL',
                      status: (_services?['postgres'] ?? 'unknown').toString(),
                    ),
                    _ServiceRow(
                      label: 'Redis',
                      status: (_services?['redis'] ?? 'unknown').toString(),
                    ),
                    _ServiceRow(
                      label: 'adminUi.superDash.aiService'.tr(),
                      status: (_services?['ai_service'] ?? 'unknown')
                          .toString(),
                    ),
                  ]),
                  const SizedBox(height: AppSpacing.lg),
                  _panel('Quick Configuration', [
                    _InfoRow(
                      label: 'adminUi.superDash.environment'.tr(),
                      value: (_info?['app_env'] ?? '--').toString(),
                    ),
                    _InfoRow(
                      label: 'Debug',
                      value: _info?['debug'] == true ? 'ON' : 'OFF',
                    ),
                    _InfoRow(
                      label: 'adminUi.superDash.logLevel'.tr(),
                      value: (_info?['log_level'] ?? '--').toString(),
                    ),
                    _InfoRow(
                      label: 'adminUi.superDash.accessToken'.tr(),
                      value: '${_info?['token_expire_minutes'] ?? '--'} min',
                    ),
                    _InfoRow(
                      label: 'Google OAuth',
                      value: _info?['google_oauth'] == true
                          ? 'ENABLED'
                          : 'DISABLED',
                    ),
                    _InfoRow(
                      label: 'Firebase',
                      value: _info?['firebase'] == true
                          ? 'ENABLED'
                          : 'DISABLED',
                    ),
                  ]),
                ],
              ),
            ),
    );
  }

  Widget _panel(String title, List<Widget> children) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: context.ac.surface,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      border: Border.all(color: context.ac.outlineVariant, width: 0.5),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );

  Widget _restricted(BuildContext context) => Scaffold(
    backgroundColor: context.ac.background,
    appBar: AppBar(
      leading: AppBackButton(
        icon: Icons.arrow_back,
        color: context.ac.onSurface,
        onPressed: () => context.pop(),
      ),
      title: Text(
        'adminUi.superDash.superAdminDashboard'.tr(),
        style: context.adminStyle(fontWeight: FontWeight.w700),
      ),
    ),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock_outlined, color: context.ac.error, size: 48),
            const SizedBox(height: AppSpacing.lg),
            Text(
              'adminUi.superDash.accessRestricted'.tr(),
              style: Theme.of(
                context,
              ).textTheme.heading?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              'adminUi.superDash.thisSectionIsOnlyAccessible'.tr(),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: context.ac.onSurfaceMuted),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ServiceRow extends StatelessWidget {
  final String label;
  final String status;
  const _ServiceRow({required this.label, required this.status});
  @override
  Widget build(BuildContext context) {
    final ok = status == 'healthy';
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: context.adminStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Icon(
            ok ? Icons.check_circle : Icons.warning_amber_rounded,
            color: ok ? context.ac.success : context.ac.warning,
            size: 18,
          ),
          const SizedBox(width: 6),
          Text(
            status.replaceAll('_', ' ').toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: ok ? context.ac.success : context.ac.warning,
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 44,
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.ac.onSurfaceMuted),
          ),
        ),
        Text(
          value,
          style: Theme.of(
            context,
          ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

class _DashboardError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _DashboardError({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: context.ac.error, size: 40),
          const SizedBox(height: AppSpacing.md),
          Text(
            'adminUi.superDash.dashboardUnavailable'.tr(),
            style: context.adminStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            message,
            textAlign: TextAlign.center,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: context.ac.onSurfaceMuted),
          ),
          const SizedBox(height: AppSpacing.lg),
          SizedBox(
            height: 44,
            child: OutlinedButton(
              onPressed: onRetry,
              child: Text('adminUi.superDash.retry'.tr()),
            ),
          ),
        ],
      ),
    ),
  );
}
