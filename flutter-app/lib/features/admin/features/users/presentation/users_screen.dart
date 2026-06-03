import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../data/users_repository.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});

  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _repo = UsersRepository();
  List<AdminUserItem> _users = [];
  int _total = 0;
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  String? _activeFilter;
  final _searchCtrl = TextEditingController();

  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load([String? search]) async {
    setState(() { _loading = true; _error = null; _page = 1; });
    try {
      final result = await _repo.getUsers(
        page: 1,
        search: search ?? (_searchCtrl.text.isEmpty ? null : _searchCtrl.text),
        status: _activeFilter,
      );
      if (mounted) {
        setState(() {
          _users = result['users'] as List<AdminUserItem>;
          _total = result['total'] as int;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = 'Không thể tải danh sách users.'; });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _users.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final nextPage = _page + 1;
      final result = await _repo.getUsers(
        page: nextPage,
        search: _searchCtrl.text.isEmpty ? null : _searchCtrl.text,
        status: _activeFilter,
      );
      if (mounted) {
        setState(() {
          _users.addAll(result['users'] as List<AdminUserItem>);
          _page = nextPage;
          _loadingMore = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  bool get _hasMore => _users.length < _total;

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _FilterSheet(
        current: _activeFilter,
        onApply: (filter) {
          setState(() => _activeFilter = filter);
          _load();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            backgroundColor: AppColors.background,
            elevation: 0,
            scrolledUnderElevation: 0,
            title: Row(
              children: [
                const Icon(Icons.language, color: AppColors.primary, size: 24),
                const SizedBox(width: 6),
                Text('LingoAdmin',
                    style: GoogleFonts.spaceGrotesk(
                        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.primary)),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.search, color: AppColors.onSurface),
                onPressed: () {},
              ),
              IconButton(
                icon: const Icon(Icons.notifications_outlined, color: AppColors.onSurface),
                onPressed: () {},
              ),
            ],
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Text(
                  'User Management',
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: AppColors.onSurface,
                    letterSpacing: -0.02,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  "Oversee LexiLingo's growing community of learners. Manage permissions, track progress.",
                  style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // Growth banner
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.primaryBright,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('TOTAL GROWTH',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 0.08,
                                  color: Colors.white60)),
                          Text('+${_total > 0 ? '24' : '0'}%',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 36,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                  letterSpacing: -0.03)),
                          Text('Since last month',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, color: Colors.white60)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_error!,
                              style: GoogleFonts.spaceGrotesk(fontSize: 13, color: AppColors.error)),
                        ),
                        GestureDetector(
                          onTap: () => _load(_searchCtrl.text.isEmpty ? null : _searchCtrl.text),
                          child: Text('Retry',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, fontWeight: FontWeight.w700, color: AppColors.error)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                // Search bar
                TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'Search users by name, email, or language...',
                    prefixIcon: const Icon(Icons.search, color: AppColors.onSurfaceMuted, size: 20),
                  ),
                  onSubmitted: _load,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    OutlinedButton.icon(
                      onPressed: _showFilterSheet,
                      icon: Icon(
                        Icons.filter_list,
                        size: 16,
                        color: _activeFilter != null ? AppColors.primary : null,
                      ),
                      label: Text(
                        _activeFilter != null
                            ? _activeFilter!.toUpperCase()
                            : 'Filter',
                        style: GoogleFonts.spaceGrotesk(
                          fontWeight: FontWeight.w600,
                          color: _activeFilter != null ? AppColors.primary : null,
                        ),
                      ),
                      style: _activeFilter != null
                          ? OutlinedButton.styleFrom(
                              side: const BorderSide(color: AppColors.primary),
                            )
                          : null,
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton.icon(
                      onPressed: () {},
                      icon: const Icon(Icons.person_add_outlined, size: 16),
                      label: Text('Add User',
                          style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                // Users list table
                Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.outlineVariant, width: 0.5),
                  ),
                  child: Column(
                    children: [
                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        child: Row(
                          children: [
                            Expanded(
                              flex: 3,
                              child: Text('User',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Status',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                            Expanded(
                              flex: 2,
                              child: Text('Level',
                                  style: GoogleFonts.spaceGrotesk(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: AppColors.onSurfaceMuted)),
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      if (_loading)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Center(child: CircularProgressIndicator(color: AppColors.primary)),
                        )
                      else if (_users.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(32),
                          child: Center(
                            child: Text('No users found',
                                style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _users.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) => _UserRow(
                            user: _users[i],
                            onTap: () => context.push('/users/${_users[i].id}/stats'),
                            onRefresh: _load,
                          ),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Showing ${_users.length} of ${_total > 0 ? _total : _users.length} users',
                              style: GoogleFonts.spaceGrotesk(
                                  fontSize: 12, color: AppColors.onSurfaceMuted),
                            ),
                            if (_hasMore)
                              _loadingMore
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        color: AppColors.primary,
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : GestureDetector(
                                      onTap: _loadMore,
                                      child: Text(
                                        'Load more',
                                        style: GoogleFonts.spaceGrotesk(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserRow extends StatefulWidget {
  final AdminUserItem user;
  final VoidCallback onTap;
  final VoidCallback? onRefresh;

  const _UserRow({required this.user, required this.onTap, this.onRefresh});

  @override
  State<_UserRow> createState() => _UserRowState();
}

class _UserRowState extends State<_UserRow> {
  final _repo = UsersRepository();

  Future<void> _toggleBlock() async {
    try {
      if (widget.user.status == 'active') {
        await _repo.blockUser(widget.user.id);
      } else {
        await _repo.unblockUser(widget.user.id);
      }
      widget.onRefresh?.call();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Thao tác thất bại',
                style: GoogleFonts.spaceGrotesk()),
            backgroundColor: AppColors.error,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Color get _statusColor {
    switch (widget.user.status) {
      case 'active':
        return AppColors.success;
      case 'blocked':
        return AppColors.error;
      default:
        return AppColors.warning;
    }
  }

  Color get _statusBg {
    switch (widget.user.status) {
      case 'active':
        return AppColors.successContainer;
      case 'blocked':
        return AppColors.errorContainer;
      default:
        return AppColors.warningContainer;
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: AppColors.primaryContainer,
                    backgroundImage: widget.user.avatarUrl != null
                        ? NetworkImage(widget.user.avatarUrl!)
                        : null,
                    child: widget.user.avatarUrl == null
                        ? Text(
                            widget.user.displayName.isNotEmpty
                                ? widget.user.displayName[0].toUpperCase()
                                : '?',
                            style: GoogleFonts.spaceGrotesk(
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                                fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.user.displayName,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: AppColors.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.user.email,
                          style: GoogleFonts.spaceGrotesk(
                              fontSize: 11, color: AppColors.onSurfaceMuted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  widget.user.statusDisplay,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.spaceGrotesk(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: _statusColor,
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                widget.user.level,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.onSurface),
              ),
            ),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, size: 18, color: AppColors.onSurfaceMuted),
              onSelected: (v) {
                if (v == 'block') _toggleBlock();
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: 'block',
                  child: Row(
                    children: [
                      Icon(
                        widget.user.status == 'active'
                            ? Icons.block_outlined
                            : Icons.check_circle_outline,
                        size: 16,
                        color: widget.user.status == 'active'
                            ? AppColors.error
                            : AppColors.success,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        widget.user.status == 'active' ? 'Block User' : 'Unblock User',
                        style: GoogleFonts.spaceGrotesk(
                          fontSize: 13,
                          color: widget.user.status == 'active'
                              ? AppColors.error
                              : AppColors.success,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterSheet extends StatefulWidget {
  final String? current;
  final ValueChanged<String?> onApply;
  const _FilterSheet({required this.current, required this.onApply});

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  String? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.current;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 20, 20, MediaQuery.of(context).padding.bottom + 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: AppColors.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Filter Users',
              style: GoogleFonts.spaceGrotesk(
                  fontSize: 18, fontWeight: FontWeight.w700,
                  color: AppColors.onSurface)),
          const SizedBox(height: 16),
          _FilterChip(
            label: 'All Users',
            selected: _selected == null,
            onTap: () => setState(() => _selected = null),
          ),
          const SizedBox(height: 8),
          _FilterChip(
            label: 'Active',
            selected: _selected == 'active',
            color: AppColors.success,
            onTap: () => setState(() => _selected = 'active'),
          ),
          const SizedBox(height: 8),
          _FilterChip(
            label: 'Inactive',
            selected: _selected == 'inactive',
            color: AppColors.warning,
            onTap: () => setState(() => _selected = 'inactive'),
          ),
          const SizedBox(height: 8),
          _FilterChip(
            label: 'Blocked',
            selected: _selected == 'blocked',
            color: AppColors.error,
            onTap: () => setState(() => _selected = 'blocked'),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onApply(_selected);
              },
              child: Text('Apply Filter',
                  style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? c.withValues(alpha: 0.08) : AppColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? c : AppColors.outlineVariant,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            if (selected)
              Icon(Icons.check_circle, color: c, size: 18)
            else
              Icon(Icons.circle_outlined, color: AppColors.onSurfaceMuted, size: 18),
            const SizedBox(width: 12),
            Text(label,
                style: GoogleFonts.spaceGrotesk(
                    fontSize: 14,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? c : AppColors.onSurface)),
          ],
        ),
      ),
    );
  }
}
