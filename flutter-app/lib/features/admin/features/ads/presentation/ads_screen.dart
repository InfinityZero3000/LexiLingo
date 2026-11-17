import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/admin_colors.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../data/banner_repository.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

const _kPositions = ['hero', 'sidebar', 'interstitial'];
const _kLevels = ['Any', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key});
  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> {
  final _repo = BannerRepository();
  List<BannerItem> _banners = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final banners = await _repo.listBanners();
      if (!mounted) return;
      setState(() {
        _banners = banners;
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Không thể tải danh sách banner.';
        });
      }
    }
  }

  void _message(String text, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text, style: GoogleFonts.spaceGrotesk()),
        backgroundColor: error ? AdminColors.error : AdminColors.success,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _delete(BannerItem item) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Xóa banner?'),
        content: Text(item.title),
        actions: [
          TextButton(
            style: TextButton.styleFrom(
              minimumSize: const Size(kMinTapTarget, kMinTapTarget),
            ),
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hủy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await _repo.deleteBanner(item.id);
      await _load();
      _message('Đã xóa banner.');
    } catch (_) {
      _message('Xóa thất bại.', error: true);
    }
  }

  Future<void> _toggleActive(BannerItem item) async {
    try {
      await _repo.updateBanner(item.id, {'is_active': !item.isActive});
      await _load();
    } catch (_) {
      _message('Cập nhật thất bại.', error: true);
    }
  }

  Future<void> _form([BannerItem? item]) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AdminColors.surface,
      builder: (_) => _BannerForm(item: item),
    );
    if (payload == null) return;
    try {
      item == null
          ? await _repo.createBanner(payload)
          : await _repo.updateBanner(item.id, payload);
      await _load();
      _message('Đã lưu banner.');
    } catch (_) {
      _message('Không thể lưu banner.', error: true);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AdminColors.background,
    appBar: AppBar(
      backgroundColor: AdminColors.background,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.menu_rounded, color: AdminColors.onSurface),
        onPressed: AdminShell.openDrawer,
      ),
      title: Text(
        'Banner & Ads',
        style: GoogleFonts.spaceGrotesk(
          fontWeight: FontWeight.w700,
          color: AdminColors.onSurface,
        ),
      ),
    ),
    floatingActionButton: FloatingActionButton.extended(
      backgroundColor: AdminColors.primary,
      foregroundColor: AdminColors.surface,
      onPressed: () => _form(),
      icon: const Icon(Icons.add),
      label: const Text('Tạo banner'),
    ),
    body: RefreshIndicator(
      color: AdminColors.primary,
      onRefresh: _load,
      child: _loading
          ? const Center(
              child: CircularProgressIndicator(color: AdminColors.primary),
            )
          : _error != null
          ? _StateCard(icon: Icons.error_outline, text: _error!, action: _load)
          : _banners.isEmpty
          ? const _StateCard(
              icon: Icons.campaign_outlined,
              text: 'Chưa có banner nào.',
            )
          : ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
              children: _banners
                  .map(
                    (b) => _BannerCard(
                      item: b,
                      onEdit: () => _form(b),
                      onDelete: () => _delete(b),
                      onToggle: () => _toggleActive(b),
                    ),
                  )
                  .toList(),
            ),
    ),
  );
}

class _BannerCard extends StatelessWidget {
  final BannerItem item;
  final VoidCallback onEdit, onDelete, onToggle;
  const _BannerCard({
    required this.item,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AdminColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AdminColors.outline),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.title,
                style: Theme.of(
                  context,
                ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Switch(value: item.isActive, onChanged: (_) => onToggle()),
          ],
        ),
        if (item.description?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              item.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.spaceGrotesk(
                color: AdminColors.onSurfaceMuted,
              ),
            ),
          ),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          children: [
            _Chip(item.position),
            _Chip('priority ${item.priority}'),
            _Chip(item.targetLanguage ?? 'any language'),
            _Chip(
              item.targetMinLevel == null && item.targetMaxLevel == null
                  ? 'any level'
                  : '${item.targetMinLevel ?? 'A1'}–${item.targetMaxLevel ?? 'C2'}',
            ),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Sửa',
              onPressed: onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
              tooltip: 'Xóa',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline, color: AdminColors.error),
            ),
          ],
        ),
      ],
    ),
  );
}

class _BannerForm extends StatefulWidget {
  final BannerItem? item;
  const _BannerForm({this.item});
  @override
  State<_BannerForm> createState() => _BannerFormState();
}

class _BannerFormState extends State<_BannerForm> {
  late final TextEditingController title,
      description,
      imageUrl,
      linkUrl,
      priority,
      targetLanguage;
  late String position, minLevel, maxLevel;
  late bool active;
  DateTime? startAt, endAt;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    title = TextEditingController(text: i?.title);
    description = TextEditingController(text: i?.description);
    imageUrl = TextEditingController(text: i?.imageUrl);
    linkUrl = TextEditingController(text: i?.linkUrl);
    priority = TextEditingController(text: '${i?.priority ?? 0}');
    targetLanguage = TextEditingController(text: i?.targetLanguage);
    position = i?.position ?? 'hero';
    minLevel = i?.targetMinLevel ?? 'Any';
    maxLevel = i?.targetMaxLevel ?? 'Any';
    active = i?.isActive ?? true;
    startAt = i?.startAt;
    endAt = i?.endAt;
  }

  Future<void> _pickDate(bool isStart) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isStart ? startAt : endAt) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() => isStart ? startAt = picked : endAt = picked);
  }

  String _fmt(DateTime? d) => d == null
      ? 'Không giới hạn'
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: widget.item == null ? 'Tạo banner' : 'Sửa banner',
    children: [
      _field(title, 'Tiêu đề *'),
      _field(description, 'Mô tả', lines: 2),
      _field(imageUrl, 'URL hình ảnh *'),
      _field(linkUrl, 'URL đích'),
      _drop(
        'Vị trí',
        position,
        _kPositions,
        (v) => setState(() => position = v),
      ),
      _field(priority, 'Độ ưu tiên', number: true),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickDate(true),
              child: Text('Từ: ${_fmt(startAt)}'),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: OutlinedButton(
              onPressed: () => _pickDate(false),
              child: Text('Đến: ${_fmt(endAt)}'),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.md),
      Row(
        children: [
          Expanded(
            child: _drop(
              'Trình độ tối thiểu',
              minLevel,
              _kLevels,
              (v) => setState(() => minLevel = v),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: _drop(
              'Trình độ tối đa',
              maxLevel,
              _kLevels,
              (v) => setState(() => maxLevel = v),
            ),
          ),
        ],
      ),
      _field(targetLanguage, 'Ngôn ngữ mục tiêu (bỏ trống = mọi ngôn ngữ)'),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: const Text('Hoạt động'),
        value: active,
        onChanged: (v) => setState(() => active = v),
      ),
      _save(context, () {
        if (title.text.trim().isEmpty || imageUrl.text.trim().isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Cần có tiêu đề và URL hình ảnh.')),
          );
          return;
        }
        Navigator.pop(context, {
          'title': title.text.trim(),
          'description': description.text.trim().isEmpty
              ? null
              : description.text.trim(),
          'image_url': imageUrl.text.trim(),
          'link_url': linkUrl.text.trim().isEmpty ? null : linkUrl.text.trim(),
          'position': position,
          'priority': int.tryParse(priority.text) ?? 0,
          'is_active': active,
          'start_at': startAt?.toUtc().toIso8601String(),
          'end_at': endAt?.toUtc().toIso8601String(),
          'target_min_level': minLevel == 'Any' ? null : minLevel,
          'target_max_level': maxLevel == 'Any' ? null : maxLevel,
          'target_language': targetLanguage.text.trim().isEmpty
              ? null
              : targetLanguage.text.trim(),
        });
      }),
    ],
  );
}

class _FormSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _FormSheet({required this.title, required this.children});
  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.lg),
            ...children,
          ],
        ),
      ),
    ),
  );
}

Widget _field(
  TextEditingController c,
  String label, {
  int lines = 1,
  bool number = false,
}) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: TextField(
    controller: c,
    maxLines: lines,
    keyboardType: number ? TextInputType.number : null,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  ),
);

Widget _drop(
  String label,
  String value,
  List<String> options,
  ValueChanged<String> change,
) => Padding(
  padding: const EdgeInsets.only(bottom: 12),
  child: DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    items: options
        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
        .toList(),
    onChanged: (v) => change(v!),
  ),
);

Widget _save(BuildContext context, VoidCallback onPressed) => SizedBox(
  height: 48,
  child: FilledButton(onPressed: onPressed, child: const Text('Lưu')),
);

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: AdminColors.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.bodySmall?.copyWith(color: AdminColors.onSurfaceMuted),
    ),
  );
}

class _StateCard extends StatelessWidget {
  final IconData icon;
  final String text;
  final Future<void> Function()? action;
  const _StateCard({required this.icon, required this.text, this.action});
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: AdminColors.onSurfaceMuted),
          const SizedBox(height: AppSpacing.md),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.spaceGrotesk(color: AdminColors.onSurfaceMuted),
          ),
          if (action != null)
            TextButton(onPressed: action, child: const Text('Thử lại')),
        ],
      ),
    ),
  );
}
