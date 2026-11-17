import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../data/logs_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class LogsScreen extends StatefulWidget {
  const LogsScreen({super.key});

  @override
  State<LogsScreen> createState() => _LogsScreenState();
}

class _LogsScreenState extends State<LogsScreen> {
  static const _actions = [
    'assign_role',
    'deactivate',
    'activate',
    'create',
    'update',
    'delete',
  ];
  static const _resourceTypes = ['user', 'course', 'role'];

  final _repo = LogsRepository();
  List<AuditLogEntry> _logs = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _action;
  String? _resourceType;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _page = 1;
    });
    try {
      final result = await _repo.getAuditLogs(
        action: _action,
        resourceType: _resourceType,
      );
      if (!mounted) return;
      setState(() {
        _logs = result['logs'] as List<AuditLogEntry>;
        _total = result['total'] as int;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Không thể tải nhật ký hệ thống.';
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _logs.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _repo.getAuditLogs(
        page: nextPage,
        action: _action,
        resourceType: _resourceType,
      );
      if (!mounted) return;
      setState(() {
        _logs.addAll(result['logs'] as List<AuditLogEntry>);
        _page = nextPage;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Không thể tải thêm nhật ký.',
            style: GoogleFonts.spaceGrotesk(),
          ),
          backgroundColor: AdminColors.error,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminColors.background,
      body: RefreshIndicator(
        color: AdminColors.primary,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AdminColors.background,
              elevation: 0,
              scrolledUnderElevation: 0,
              leading: IconButton(
                icon: const Icon(
                  Icons.menu_rounded,
                  color: AdminColors.onSurface,
                ),
                onPressed: AdminShell.openDrawer,
              ),
              title: Text(
                'Audit Logs',
                style: GoogleFonts.spaceGrotesk(
                  fontWeight: FontWeight.w700,
                  color: AdminColors.onSurface,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              sliver: SliverList(
                delegate: SliverChildListDelegate([
                  Text(
                    'System activity',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: AdminColors.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '$_total audit events • ${_logs.length} loaded',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: AdminColors.onSurfaceMuted,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Action',
                          value: _action,
                          options: _actions,
                          onChanged: (value) {
                            setState(() => _action = value);
                            _load();
                          },
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: _FilterDropdown(
                          label: 'Resource',
                          value: _resourceType,
                          options: _resourceTypes,
                          onChanged: (value) {
                            setState(() => _resourceType = value);
                            _load();
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  if (_error != null)
                    _ErrorCard(message: _error!, onRetry: _load)
                  else if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(48),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AdminColors.primary,
                        ),
                      ),
                    )
                  else if (_logs.isEmpty)
                    const _EmptyState()
                  else ...[
                    ..._logs.map(
                      (log) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _LogCard(log: log),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: AdminColors.surface,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        border: Border.all(
                          color: AdminColors.outlineVariant,
                          width: 0.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_logs.length} / $_total events',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: AdminColors.onSurfaceMuted),
                          ),
                          if (_logs.length < _total)
                            TextButton(
                              onPressed: _loadingMore ? null : _loadMore,
                              child: _loadingMore
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: AdminColors.primary,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      'Load more',
                                      style: GoogleFonts.spaceGrotesk(
                                        fontWeight: FontWeight.w700,
                                        color: AdminColors.primary,
                                      ),
                                    ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<String> options;
  final ValueChanged<String?> onChanged;

  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurface),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
        isDense: true,
      ),
      items: [
        DropdownMenuItem<String>(
          value: null,
          child: Text('All', style: GoogleFonts.spaceGrotesk()),
        ),
        ...options.map(
          (option) => DropdownMenuItem(
            value: option,
            child: Text(
              option.replaceAll('_', ' '),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(),
            ),
          ),
        ),
      ],
      onChanged: onChanged,
    );
  }
}

class _LogCard extends StatelessWidget {
  final AuditLogEntry log;

  const _LogCard({required this.log});

  String _shortId(String? value) {
    if (value == null || value.isEmpty) return '—';
    return value.length > 8 ? '${value.substring(0, 8)}…' : value;
  }

  String get _timestamp {
    final date = DateTime.tryParse(log.createdAt)?.toLocal();
    return date == null
        ? log.createdAt
        : DateFormat('dd/MM/yyyy HH:mm').format(date);
  }

  Color get _actionColor {
    switch (log.action) {
      case 'activate':
        return AdminColors.success;
      case 'deactivate':
      case 'delete':
        return AdminColors.error;
      case 'assign_role':
        return AdminColors.warning;
      default:
        return AdminColors.primary;
    }
  }

  Color get _actionBackground {
    switch (log.action) {
      case 'activate':
        return AdminColors.successContainer;
      case 'deactivate':
      case 'delete':
        return AdminColors.errorContainer;
      case 'assign_role':
        return AdminColors.warningContainer;
      default:
        return AdminColors.primaryContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                decoration: BoxDecoration(
                  color: _actionBackground,
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Text(
                  log.action.replaceAll('_', ' ').toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: _actionColor,
                  ),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.schedule,
                size: 14,
                color: AdminColors.onSurfaceMuted,
              ),
              const SizedBox(width: 5),
              Text(
                _timestamp,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: AdminColors.onSurfaceMuted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _Meta(label: 'RESOURCE', value: log.resourceType),
              ),
              Expanded(
                child: _Meta(
                  label: 'RESOURCE ID',
                  value: _shortId(log.resourceId),
                ),
              ),
              Expanded(
                child: _Meta(label: 'ADMIN ID', value: _shortId(log.userId)),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'DETAILS',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: AdminColors.onSurfaceMuted,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            log.details?.isNotEmpty == true ? log.details! : '—',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: AdminColors.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;

  const _Meta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: AdminColors.onSurfaceMuted,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: AdminColors.onSurface,
          ),
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AdminColors.errorContainer,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AdminColors.error),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: AdminColors.error),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(
              'Retry',
              style: GoogleFonts.spaceGrotesk(
                fontWeight: FontWeight.w700,
                color: AdminColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: AdminColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AdminColors.outlineVariant, width: 0.5),
      ),
      child: Column(
        children: [
          const Icon(
            Icons.manage_search_outlined,
            size: 36,
            color: AdminColors.onSurfaceMuted,
          ),
          const SizedBox(height: 10),
          Text(
            'No audit logs found',
            style: GoogleFonts.spaceGrotesk(
              fontWeight: FontWeight.w700,
              color: AdminColors.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Try changing the active filters.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
          ),
        ],
      ),
    );
  }
}
