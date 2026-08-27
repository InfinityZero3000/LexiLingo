import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/widgets/app_back_button.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/admin_skeleton.dart';
import '../../../shared/widgets/stat_card.dart';
import '../../auth/presentation/auth_provider.dart';
import '../data/users_repository.dart';

class UserStatsScreen extends StatefulWidget {
  final String userId;
  const UserStatsScreen({super.key, required this.userId});
  @override
  State<UserStatsScreen> createState() => _UserStatsScreenState();
}

class _UserStatsScreenState extends State<UserStatsScreen> {
  final _repo = UsersRepository();
  Map<String, dynamic>? _user;
  List<Map<String, dynamic>> _activity = [];
  bool _loading = true, _acting = false;
  String? _error;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final results = await Future.wait([_repo.getUserStats(widget.userId), _repo.getUserActivity(widget.userId)]);
      if (mounted) setState(() { _user = results[0] as Map<String, dynamic>; _activity = results[1] as List<Map<String, dynamic>>; _loading = false; });
    } catch (_) {
      if (mounted) setState(() { _loading = false; _error = 'Không thể tải chi tiết người dùng.'; });
    }
  }

  Future<bool> _confirm(String title, String message) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Hủy')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Xác nhận')),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _setActive() async {
    final next = _user?['is_active'] != true;
    final name = _user?['display_name'] ?? _user?['email'] ?? 'người dùng này';
    final ok = await _confirm(
      next ? 'Kích hoạt tài khoản?' : 'Tạm dừng tài khoản?',
      next
          ? 'Kích hoạt lại tài khoản của $name?'
          : 'Tạm dừng tài khoản của $name? Người dùng sẽ không thể đăng nhập cho đến khi được kích hoạt lại.',
    );
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    try { await _repo.setUserActive(widget.userId, next); await _load(); _notice(next ? 'Đã kích hoạt tài khoản' : 'Đã tạm dừng tài khoản', false); }
    catch (_) { _notice('Không thể cập nhật trạng thái', true); }
    if (mounted) setState(() => _acting = false);
  }

  Future<void> _setRole(int level) async {
    final name = _user?['display_name'] ?? _user?['email'] ?? 'người dùng này';
    final ok = await _confirm('Đổi vai trò?', 'Đổi vai trò của $name thành "${_roleLabel(level)}"?');
    if (!ok || !mounted) return;
    setState(() => _acting = true);
    try { await _repo.updateRole(widget.userId, level); await _load(); _notice('Đã cập nhật vai trò', false); }
    catch (_) { _notice('Chỉ Super Admin mới có thể đổi vai trò', true); }
    if (mounted) setState(() => _acting = false);
  }

  void _notice(String text, bool error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text, style: GoogleFonts.spaceGrotesk()),
      backgroundColor: error ? AppColors.error : AppColors.success, behavior: SnackBarBehavior.floating));
  }

  String _date(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    return date == null ? 'Chưa có' : '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.background,
    appBar: AppBar(
      leading: AppBackButton(icon: Icons.arrow_back, color: AppColors.onSurface, onPressed: context.pop),
      title: Text('Chi tiết người dùng', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
    ),
    body: RefreshIndicator(onRefresh: _load, child: _loading
      ? ListView(padding: const EdgeInsets.all(16), children: const [SectionCardSkeleton(contentHeight: 160), SizedBox(height: 12), SectionCardSkeleton(contentHeight: 240)])
      : _error != null ? ListView(children: [SizedBox(height: 360, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(_error!), const SizedBox(height: 12), ElevatedButton(onPressed: _load, child: const Text('Thử lại'))])))])
      : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 64), children: [
          _profile(), const SizedBox(height: 12), _metrics(), const SizedBox(height: 12), _account(), const SizedBox(height: 12), _activities(),
        ])),
  );

  Widget _profile() => Container(
    padding: const EdgeInsets.all(20), decoration: _box(),
    child: Column(children: [
      CircleAvatar(radius: 38, backgroundColor: AppColors.primaryContainer,
        backgroundImage: _user?['avatar_url'] == null ? null : NetworkImage(_user!['avatar_url']),
        child: _user?['avatar_url'] == null ? Text((_user?['display_name'] ?? _user?['email'] ?? '?')[0].toUpperCase(),
          style: GoogleFonts.spaceGrotesk(fontSize: 26, fontWeight: FontWeight.w700, color: AppColors.primary)) : null),
      const SizedBox(height: 10),
      Text(_user?['display_name'] ?? _user?['username'] ?? 'Người dùng', style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
      Text(_user?['email'] ?? '', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
      const SizedBox(height: 12),
      Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
        _pill(_user?['is_verified'] == true ? 'Đã xác minh' : 'Chưa xác minh', _user?['is_verified'] == true ? AppColors.success : AppColors.warning),
        _pill(_user?['is_active'] == true ? 'Hoạt động' : 'Tạm dừng', _user?['is_active'] == true ? AppColors.success : AppColors.onSurfaceMuted),
        _pill(_roleLabel(_user?['role_level'] ?? 0), AppColors.primary),
      ]),
    ]),
  );

  Widget _metrics() => GridView.count(
    shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), crossAxisCount: 2,
    mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 1.35,
    children: [
      StatCard(label: 'Tổng XP', value: '${_user?['total_xp'] ?? 0}', icon: Icons.star_outline),
      StatCard(label: 'Khóa học', value: '${_user?['courses_completed'] ?? 0}/${_user?['courses_enrolled'] ?? 0}', icon: Icons.school_outlined),
      StatCard(label: 'Bài học', value: '${_user?['lessons_completed'] ?? 0}', icon: Icons.menu_book_outlined),
      StatCard(label: 'Ngày hoạt động', value: '${_user?['daily_activities'] ?? 0}', icon: Icons.calendar_today_outlined),
    ],
  );

  Widget _account() {
    final isSuperAdmin = context.watch<AuthProvider>().isSuperAdmin;
    final maxLevel = isSuperAdmin ? 2 : 1;
    return Container(
    padding: const EdgeInsets.all(16), decoration: _box(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Tài khoản & quyền', style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      _line('Ngày tham gia', _date(_user?['created_at'])),
      _line('Đăng nhập cuối', _date(_user?['last_login'])),
      _line('Nhà cung cấp', ((_user?['provider'] as List?) ?? const ['local']).join(', ')),
      const Divider(height: 28),
      Text('Thay đổi vai trò', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: List.generate(maxLevel + 1, (level) => SizedBox(height: 44, child: OutlinedButton(
        onPressed: _acting || _user?['role_level'] == level ? null : () => _setRole(level), child: Text(_roleLabel(level)),
      )))),
      const SizedBox(height: 12),
      SizedBox(width: double.infinity, height: 48, child: ElevatedButton.icon(
        onPressed: _acting ? null : _setActive,
        style: ElevatedButton.styleFrom(backgroundColor: _user?['is_active'] == true ? AppColors.error : AppColors.success),
        icon: Icon(_user?['is_active'] == true ? Icons.pause_circle_outline : Icons.check_circle_outline),
        label: Text(_user?['is_active'] == true ? 'Tạm dừng tài khoản' : 'Kích hoạt tài khoản'),
      )),
    ]),
    );
  }

  Widget _activities() => Container(
    padding: const EdgeInsets.all(16), decoration: _box(), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Hoạt động gần đây', style: GoogleFonts.spaceGrotesk(fontSize: 17, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      if (_activity.isEmpty) Padding(padding: const EdgeInsets.symmetric(vertical: 24), child: Center(child: Text('Chưa có hoạt động', style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted))))
      else ..._activity.map((item) => ListTile(
        contentPadding: EdgeInsets.zero, minLeadingWidth: 44,
        leading: CircleAvatar(backgroundColor: AppColors.primaryContainer, child: Icon(item['activity_type'] == 'lesson_completed' ? Icons.menu_book : Icons.bolt, color: AppColors.primary)),
        title: Text(item['description'] ?? '', style: GoogleFonts.spaceGrotesk(fontSize: 13, fontWeight: FontWeight.w600)),
        subtitle: Text(_date(item['activity_date']), style: GoogleFonts.spaceGrotesk(fontSize: 12)),
        trailing: (item['xp_earned'] ?? 0) > 0 ? Text('+${item['xp_earned']} XP', style: GoogleFonts.spaceGrotesk(color: AppColors.primary, fontWeight: FontWeight.w700)) : null,
      )),
    ]),
  );

  BoxDecoration _box() => BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: AppColors.outlineVariant));
  Widget _pill(String text, Color color) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: GoogleFonts.spaceGrotesk(fontSize: 12, fontWeight: FontWeight.w700, color: color)));
  Widget _line(String label, String value) => Padding(padding: const EdgeInsets.symmetric(vertical: 7), child: Row(children: [
    Expanded(child: Text(label, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted))),
    Flexible(child: Text(value, textAlign: TextAlign.end, style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w600))),
  ]));
  String _roleLabel(int level) => const ['User', 'Admin', 'Super Admin'][level.clamp(0, 2)];
}
