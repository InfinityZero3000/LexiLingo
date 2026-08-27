import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../../shared/widgets/staggered_entrance.dart';
import '../data/users_repository.dart';

class UsersScreen extends StatefulWidget {
  const UsersScreen({super.key});
  @override
  State<UsersScreen> createState() => _UsersScreenState();
}

class _UsersScreenState extends State<UsersScreen> {
  final _repo = UsersRepository();
  final _search = TextEditingController();
  final _selected = <String>{};
  List<AdminUserItem> _users = [];
  int _page = 1, _total = 0;
  int? _role;
  bool? _active;
  bool _loading = true, _more = false, _acting = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { _search.dispose(); super.dispose(); }

  Future<void> _load({bool append = false}) async {
    if (append) {
      setState(() => _more = true);
    } else {
      setState(() { _loading = true; _error = null; _page = 1; });
    }
    try {
      final page = append ? _page + 1 : 1;
      final result = await _repo.getUsers(
        page: page, search: _search.text.trim(), role: _role, isActive: _active,
      );
      if (!mounted) return;
      setState(() {
        final items = result['users'] as List<AdminUserItem>;
        _users = append ? [..._users, ...items] : items;
        _page = page;
        _total = result['total'] as int;
        _loading = false; _more = false;
        _selected.removeWhere((id) => !_users.any((user) => user.id == id));
      });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _more = false; _error = 'Không thể tải danh sách người dùng.'; });
    }
  }

  Future<void> _bulk(String action) async {
    final count = _selected.length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'activate' ? 'Kích hoạt $count tài khoản?' : 'Tạm dừng $count tài khoản?'),
        content: Text(action == 'activate'
            ? 'Kích hoạt lại $count tài khoản đã chọn?'
            : 'Tạm dừng $count tài khoản đã chọn? Họ sẽ không thể đăng nhập cho đến khi được kích hoạt lại.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _acting = true);
    try {
      await _repo.bulkAction(_selected, action);
      _selected.clear();
      await _load();
      _notice(action == 'activate' ? 'Đã kích hoạt người dùng' : 'Đã hủy kích hoạt người dùng', false);
    } catch (_) { _notice('Thao tác hàng loạt thất bại', true); }
    if (mounted) setState(() => _acting = false);
  }

  void _notice(String text, bool error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(text, style: GoogleFonts.spaceGrotesk()),
      backgroundColor: error ? AppColors.error : AppColors.success,
      behavior: SnackBarBehavior.floating,
    ));
  }

  void _filters() => showModalBottomSheet<void>(
    context: context, isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (context) => StatefulBuilder(builder: (context, setSheet) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Bộ lọc người dùng', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Text('Vai trò', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
          Wrap(spacing: 8, children: [null, 0, 1, 2].map((value) => ChoiceChip(
            label: Text(value == null ? 'Tất cả' : const ['User', 'Admin', 'Super Admin'][value]),
            selected: _role == value, onSelected: (_) => setSheet(() => _role = value),
          )).toList()),
          const SizedBox(height: 12),
          Text('Trạng thái', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
          Wrap(spacing: 8, children: [null, true, false].map((value) => ChoiceChip(
            label: Text(value == null ? 'Tất cả' : value ? 'Hoạt động' : 'Tạm dừng'),
            selected: _active == value, onSelected: (_) => setSheet(() => _active = value),
          )).toList()),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, height: 48, child: ElevatedButton(
            onPressed: () { Navigator.pop(context); _load(); }, child: const Text('Áp dụng'),
          )),
        ]),
      ),
    )),
  );

  @override
  Widget build(BuildContext context) {
    final activeCount = _users.where((user) => user.isActive).length;
    final totalXp = _users.fold<int>(0, (sum, user) => sum + user.totalXp);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        leading: IconButton(onPressed: AdminShell.openDrawer, icon: const Icon(Icons.menu_rounded)),
        title: Text('Quản lý người dùng', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 96), children: [
          if (_loading) ...List.generate(4, (_) => const Padding(padding: EdgeInsets.only(bottom: 12), child: ListRowSkeleton())) else ...[
            GridView.count(
              shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2,
              mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35,
              children: [
                StatCard(label: 'Tổng người dùng', value: '$_total', icon: Icons.people_outline),
                StatCard(label: 'Đang hoạt động', value: '$activeCount', icon: Icons.check_circle_outline),
                StatCard(label: 'Tạm dừng', value: '${_users.length - activeCount}', icon: Icons.pause_circle_outline),
                StatCard(label: 'XP trung bình', value: '${_users.isEmpty ? 0 : totalXp ~/ _users.length}', icon: Icons.star_outline),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _load(),
              decoration: InputDecoration(hintText: 'Tìm theo tên hoặc email', prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(onPressed: _filters, icon: const Icon(Icons.tune))),
            ),
            if (_selected.isNotEmpty) Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Expanded(child: Text('${_selected.length} đã chọn', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700))),
                SizedBox(height: 44, child: OutlinedButton(onPressed: _acting ? null : () => _bulk('activate'), child: const Text('Kích hoạt'))),
                const SizedBox(width: 8),
                SizedBox(height: 44, child: OutlinedButton(onPressed: _acting ? null : () => _bulk('deactivate'), child: const Text('Tạm dừng'))),
              ]),
            ),
            if (_error != null) Padding(
              padding: const EdgeInsets.only(top: 16),
              child: ListTile(tileColor: AppColors.errorContainer, leading: const Icon(Icons.error_outline, color: AppColors.error),
                title: Text(_error!), trailing: TextButton(onPressed: _load, child: const Text('Thử lại'))),
            ) else if (_users.isEmpty) Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Column(children: [const Icon(Icons.people_outline, size: 48, color: AppColors.onSurfaceMuted),
                const SizedBox(height: 12), Text('Không tìm thấy người dùng', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))]),
            ) else ...[
              const SizedBox(height: 12),
              ..._users.asMap().entries.map((entry) => StaggeredEntrance(index: entry.key, child: Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _UserCard(user: entry.value, selected: _selected.contains(entry.value.id),
                  onSelect: (selected) => setState(() => selected ? _selected.add(entry.value.id) : _selected.remove(entry.value.id)),
                  onOpen: () => context.push('/users/${entry.value.id}/stats').then((_) => _load())),
              ))),
              if (_users.length < _total) Center(child: SizedBox(height: 44, child: TextButton(
                onPressed: _more ? null : () => _load(append: true), child: _more ? const CircularProgressIndicator() : const Text('Tải thêm'),
              ))),
            ],
          ],
        ]),
      ),
    );
  }
}

class _UserCard extends StatelessWidget {
  final AdminUserItem user;
  final bool selected;
  final ValueChanged<bool> onSelect;
  final VoidCallback onOpen;
  const _UserCard({required this.user, required this.selected, required this.onSelect, required this.onOpen});

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface, borderRadius: BorderRadius.circular(16),
    child: InkWell(onTap: onOpen, borderRadius: BorderRadius.circular(16), child: Padding(
      padding: const EdgeInsets.all(14), child: Row(children: [
        Checkbox(value: selected, onChanged: (value) => onSelect(value ?? false)),
        CircleAvatar(radius: 22, backgroundColor: AppColors.primaryContainer,
          backgroundImage: (user.avatarUrl?.trim().isNotEmpty ?? false) ? NetworkImage(user.avatarUrl!.trim()) : null,
          onBackgroundImageError: (user.avatarUrl?.trim().isNotEmpty ?? false) ? (_, __) {} : null,
          // Initial is always the child so it still shows if the network
          // avatar fails to load — onBackgroundImageError only silences the
          // exception, it can't swap in a fallback.
          child: Text((user.displayName.isEmpty ? user.email : user.displayName)[0].toUpperCase())),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(user.displayName.isEmpty ? user.email.split('@').first : user.displayName,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          Text(user.email, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: GoogleFonts.spaceGrotesk(fontSize: 12, color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 6),
          Text('${user.roleLabel} • ${user.totalXp} XP • ${user.streakDays} ngày streak',
            style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceVariant)),
        ])),
        const SizedBox(width: 8),
        Icon(user.isActive ? Icons.check_circle : Icons.pause_circle,
          color: user.isActive ? AppColors.success : AppColors.onSurfaceMuted, size: 22),
      ]),
    )),
  );
}
