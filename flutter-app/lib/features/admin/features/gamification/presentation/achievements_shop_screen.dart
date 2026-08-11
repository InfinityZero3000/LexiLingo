import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/constants/api_endpoints.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/network/api_client.dart';
import '../../../shared/widgets/admin_shell.dart';

class AchievementsShopScreen extends StatefulWidget {
  const AchievementsShopScreen({super.key});

  @override
  State<AchievementsShopScreen> createState() => _AchievementsShopScreenState();
}

class _AchievementsShopScreenState extends State<AchievementsShopScreen> {
  List<Map<String, dynamic>> _achievements = [];
  List<Map<String, dynamic>> _shopItems = [];
  bool _loading = true;
  String? _error;
  String _category = '';

  static const _categories = [
    'lessons', 'streak', 'vocabulary', 'xp', 'quiz', 'course', 'voice',
    'level', 'special', 'skill', 'social', 'milestone',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() { _loading = true; _error = null; });
    try {
      final responses = await Future.wait([
        ApiClient.instance.get(ApiEndpoints.adminAchievements),
        ApiClient.instance.get(ApiEndpoints.adminShop, params: {'include_unavailable': true}),
      ]);
      final achievements = responses[0]['data'];
      final shop = responses[1]['data'];
      if (!mounted) return;
      setState(() {
        _achievements = _asList(achievements, 'achievements');
        _shopItems = _asList(shop, 'shop_items');
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not load gamification data.\n$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  static List<Map<String, dynamic>> _asList(dynamic data, String fallbackKey) {
    final value = data is Map ? data['items'] ?? data[fallbackKey] ?? [] : data ?? [];
    return List<Map<String, dynamic>>.from(value as List);
  }

  Future<void> _delete(String endpoint, Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${item['name']}”?', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
        content: Text('This action cannot be undone.', style: GoogleFonts.spaceGrotesk()),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true) return;
    await _run(() => ApiClient.instance.delete('$endpoint/${item['id']}'));
  }

  Future<void> _toggleAchievement(Map<String, dynamic> item) => _run(() async {
        await ApiClient.instance.dio.put(
          '${ApiEndpoints.adminAchievements}/${item['id']}',
          queryParameters: {'is_hidden': item['is_hidden'] != true},
        );
      });

  Future<void> _toggleShop(Map<String, dynamic> item) => _run(() async {
        await ApiClient.instance.put('${ApiEndpoints.adminShop}/${item['id']}', data: {
          'is_available': item['is_available'] != true,
        });
      });

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
      await _load();
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Action failed: $error')));
    }
  }

  void _showAchievementForm([Map<String, dynamic>? item]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AchievementForm(item: item, onSaved: _load),
    );
  }

  void _showShopForm([Map<String, dynamic>? item]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopForm(item: item, onSaved: _load),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.background,
          leading: IconButton(icon: const Icon(Icons.menu_rounded), onPressed: AdminShell.openDrawer),
          title: Text('Achievements & Shop', style: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700)),
          actions: [IconButton(onPressed: _load, tooltip: 'Refresh', icon: const Icon(Icons.refresh_outlined))],
          bottom: TabBar(
            labelStyle: GoogleFonts.spaceGrotesk(fontWeight: FontWeight.w700),
            tabs: const [Tab(text: 'Achievements'), Tab(text: 'Shop')],
          ),
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
            : _error != null
                ? _MessageState(message: _error!, onRetry: _load)
                : TabBarView(children: [_achievementsTab(), _shopTab()]),
      ),
    );
  }

  Widget _achievementsTab() {
    final items = _category.isEmpty
        ? _achievements
        : _achievements.where((item) => item['category'] == _category).toList();
    return RefreshIndicator(
      onRefresh: _load,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(children: [
              Expanded(child: DropdownButtonFormField<String>(
                initialValue: _category,
                decoration: const InputDecoration(labelText: 'Category'),
                items: ['', ..._categories].map((value) => DropdownMenuItem(value: value, child: Text(value.isEmpty ? 'All (${_achievements.length})' : value))).toList(),
                onChanged: (value) => setState(() => _category = value ?? ''),
              )),
              const SizedBox(width: 12),
              SizedBox(height: 48, child: FilledButton.icon(onPressed: () => _showAchievementForm(), icon: const Icon(Icons.add), label: const Text('New'))),
            ]),
          )),
          if (items.isEmpty)
            const SliverFillRemaining(hasScrollBody: false, child: _EmptyState(icon: Icons.military_tech_outlined, text: 'No achievements found'))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              sliver: SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, index) => _achievementCard(items[index]),
              ),
            ),
        ],
      ),
    );
  }

  Widget _achievementCard(Map<String, dynamic> item) {
    final hidden = item['is_hidden'] == true;
    final icon = (item['badge_icon'] ?? '').toString();
    return _Card(
      onTap: () => _showAchievementForm(item),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _RemoteIcon(url: icon, fallback: Icons.military_tech),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['name'] ?? ''}', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${item['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Chip('${item['category'] ?? '—'}'),
            _Chip('${item['rarity'] ?? 'common'}'),
            _Chip('${item['condition_type'] ?? '—'} ≥ ${item['condition_value'] ?? 1}'),
            _Chip('${item['xp_reward'] ?? 0} XP · ${item['gems_reward'] ?? 0} gems'),
          ]),
        ])),
        Column(children: [
          Switch(value: !hidden, onChanged: (_) => _toggleAchievement(item)),
          SizedBox(width: 44, height: 44, child: IconButton(tooltip: 'Delete', onPressed: () => _delete(ApiEndpoints.adminAchievements, item), icon: const Icon(Icons.delete_outline, color: AppColors.error))),
        ]),
      ]),
    );
  }

  Widget _shopTab() => RefreshIndicator(
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Expanded(child: Text('${_shopItems.length} inventory items', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700))),
                SizedBox(height: 48, child: FilledButton.icon(onPressed: () => _showShopForm(), icon: const Icon(Icons.add), label: const Text('New item'))),
              ]),
            )),
            if (_shopItems.isEmpty)
              const SliverFillRemaining(hasScrollBody: false, child: _EmptyState(icon: Icons.storefront_outlined, text: 'No shop items yet'))
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList.separated(
                  itemCount: _shopItems.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _shopCard(_shopItems[index]),
                ),
              ),
          ],
        ),
      );

  Widget _shopCard(Map<String, dynamic> item) {
    final available = item['is_available'] == true;
    final stock = item['stock_quantity'];
    return _Card(
      onTap: () => _showShopForm(item),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _RemoteIcon(url: '${item['icon_url'] ?? ''}', fallback: Icons.shopping_bag_outlined),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${item['name'] ?? ''}', style: GoogleFonts.spaceGrotesk(fontSize: 16, fontWeight: FontWeight.w700)),
          Text('${item['description'] ?? ''}', maxLines: 2, overflow: TextOverflow.ellipsis, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            _Chip('${item['item_type'] ?? '—'}'),
            _Chip('${item['price_gems'] ?? 0} gems'),
            _Chip(stock == null ? 'Unlimited stock' : '$stock in stock'),
          ]),
        ])),
        Column(children: [
          Switch(value: available, onChanged: (_) => _toggleShop(item)),
          SizedBox(width: 44, height: 44, child: IconButton(tooltip: 'Delete', onPressed: () => _delete(ApiEndpoints.adminShop, item), icon: const Icon(Icons.delete_outline, color: AppColors.error))),
        ]),
      ]),
    );
  }
}

class _AchievementForm extends StatefulWidget {
  final Map<String, dynamic>? item;
  final Future<void> Function() onSaved;
  const _AchievementForm({this.item, required this.onSaved});

  @override
  State<_AchievementForm> createState() => _AchievementFormState();
}

class _AchievementFormState extends State<_AchievementForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _icon, _color, _conditionValue, _xp, _gems;
  late String _condition, _category, _rarity;
  late bool _hidden;
  bool _saving = false;

  static const _conditions = [
    'lesson_complete', 'reach_streak', 'vocab_mastered', 'xp_earned', 'perfect_score',
    'first_perfect', 'course_complete', 'voice_practice', 'numeric_level',
    'study_time_night', 'study_time_morning', 'speed_lesson', 'grammar_mastered',
    'culture_lesson', 'writing_complete', 'listening_complete', 'social_interaction',
    'chat_complete', 'help_others', 'daily_challenge_complete', 'comeback',
  ];
  static const _categories = _AchievementsShopScreenState._categories;
  static const _rarities = ['common', 'rare', 'epic', 'legendary'];

  @override
  void initState() {
    super.initState();
    final item = widget.item ?? {};
    _name = TextEditingController(text: '${item['name'] ?? ''}');
    _description = TextEditingController(text: '${item['description'] ?? ''}');
    _icon = TextEditingController(text: '${item['badge_icon'] ?? ''}');
    _color = TextEditingController(text: '${item['badge_color'] ?? '#4CAF50'}');
    _conditionValue = TextEditingController(text: '${item['condition_value'] ?? 1}');
    _xp = TextEditingController(text: '${item['xp_reward'] ?? 0}');
    _gems = TextEditingController(text: '${item['gems_reward'] ?? 0}');
    _condition = '${item['condition_type'] ?? _conditions.first}';
    _category = '${item['category'] ?? _categories.first}';
    _rarity = '${item['rarity'] ?? _rarities.first}';
    _hidden = item['is_hidden'] == true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _description, _icon, _color, _conditionValue, _xp, _gems]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    setState(() => _saving = true);
    final values = <String, dynamic>{
      'name': _name.text.trim(), 'description': _description.text.trim(),
      'badge_icon': _icon.text.trim(), 'badge_color': _color.text.trim(),
      'condition_type': _condition, 'condition_value': int.parse(_conditionValue.text),
      'category': _category, 'rarity': _rarity, 'xp_reward': int.parse(_xp.text),
      'gems_reward': int.parse(_gems.text), 'is_hidden': _hidden,
    };
    try {
      final id = widget.item?['id'];
      await ApiClient.instance.dio.request(
        id == null ? ApiEndpoints.adminAchievements : '${ApiEndpoints.adminAchievements}/$id',
        options: Options(method: id == null ? 'POST' : 'PUT'),
        queryParameters: values,
      );
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: widget.item == null ? 'New achievement' : 'Edit achievement',
    saving: _saving,
    onSave: _save,
    child: Form(key: _key, child: Column(children: [
      _Field(controller: _name, label: 'Name', required: true),
      _Field(controller: _description, label: 'Description', required: true, lines: 2),
      _Field(controller: _icon, label: 'Badge icon URL'),
      _Field(controller: _color, label: 'Badge color'),
      _Dropdown(label: 'Condition', value: _condition, values: _conditions, onChanged: (v) => setState(() => _condition = v)),
      _Field(controller: _conditionValue, label: 'Condition value', number: true, required: true),
      _Dropdown(label: 'Category', value: _category, values: _categories, onChanged: (v) => setState(() => _category = v)),
      _Dropdown(label: 'Rarity', value: _rarity, values: _rarities, onChanged: (v) => setState(() => _rarity = v)),
      Row(children: [Expanded(child: _Field(controller: _xp, label: 'XP reward', number: true, required: true)), const SizedBox(width: 12), Expanded(child: _Field(controller: _gems, label: 'Gem reward', number: true, required: true))]),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Hidden until unlocked', style: GoogleFonts.spaceGrotesk()), value: _hidden, onChanged: (v) => setState(() => _hidden = v)),
    ])),
  );
}

class _ShopForm extends StatefulWidget {
  final Map<String, dynamic>? item;
  final Future<void> Function() onSaved;
  const _ShopForm({this.item, required this.onSaved});

  @override
  State<_ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends State<_ShopForm> {
  final _key = GlobalKey<FormState>();
  late final TextEditingController _name, _description, _price, _stock, _icon, _effects;
  late String _type;
  late bool _available;
  bool _saving = false;
  String? _effectsError;

  static const _types = [
    'streak_freeze', 'double_xp', 'hint_pack', 'heart_refill', 'avatar', 'theme',
    'time_freeze', 'extra_time', 'skip_token', 'reveal_hint', 'translate_hint',
    'mistake_shield', 'extra_heart', 'lucky_clover', 'score_multiplier', 'pair_swap',
  ];

  @override
  void initState() {
    super.initState();
    final item = widget.item ?? {};
    _name = TextEditingController(text: '${item['name'] ?? ''}');
    _description = TextEditingController(text: '${item['description'] ?? ''}');
    _price = TextEditingController(text: '${item['price_gems'] ?? 50}');
    _stock = TextEditingController(text: item['stock_quantity']?.toString() ?? '');
    _icon = TextEditingController(text: '${item['icon_url'] ?? ''}');
    _effects = TextEditingController(text: const JsonEncoder.withIndent('  ').convert(item['effects'] ?? {}));
    _type = '${item['item_type'] ?? _types.first}';
    _available = item.isEmpty || item['is_available'] == true;
  }

  @override
  void dispose() {
    for (final controller in [_name, _description, _price, _stock, _icon, _effects]) { controller.dispose(); }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_key.currentState!.validate()) return;
    dynamic effects;
    try { effects = jsonDecode(_effects.text.trim().isEmpty ? '{}' : _effects.text); }
    catch (_) { setState(() => _effectsError = 'Effects must be valid JSON.'); return; }
    if (effects is! Map) { setState(() => _effectsError = 'Effects must be a JSON object.'); return; }
    setState(() { _saving = true; _effectsError = null; });
    final values = <String, dynamic>{
      'name': _name.text.trim(), 'description': _description.text.trim(),
      'item_type': _type, 'price_gems': int.parse(_price.text),
      'is_available': _available, 'stock_quantity': _stock.text.trim().isEmpty ? null : int.parse(_stock.text),
      'icon_url': _icon.text.trim().isEmpty ? null : _icon.text.trim(), 'effects': effects,
    };
    try {
      final id = widget.item?['id'];
      if (id == null) {
        await ApiClient.instance.post(ApiEndpoints.adminShop, data: values);
      } else {
        await ApiClient.instance.put('${ApiEndpoints.adminShop}/$id', data: values);
      }
      await widget.onSaved();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $error')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => _FormSheet(
    title: widget.item == null ? 'New shop item' : 'Edit shop item',
    saving: _saving,
    onSave: _save,
    child: Form(key: _key, child: Column(children: [
      _Dropdown(label: 'Item type', value: _type, values: _types, enabled: widget.item == null, onChanged: (v) => setState(() => _type = v)),
      _Field(controller: _name, label: 'Name', required: true),
      _Field(controller: _description, label: 'Description', required: true, lines: 2),
      Row(children: [Expanded(child: _Field(controller: _price, label: 'Price (gems)', number: true, required: true)), const SizedBox(width: 12), Expanded(child: _Field(controller: _stock, label: 'Stock (blank = ∞)', number: true))]),
      _Field(controller: _icon, label: 'Icon URL'),
      _Field(controller: _effects, label: 'Effects JSON', lines: 4, errorText: _effectsError),
      SwitchListTile(contentPadding: EdgeInsets.zero, title: Text('Available for sale', style: GoogleFonts.spaceGrotesk()), value: _available, onChanged: (v) => setState(() => _available = v)),
    ])),
  );
}

class _FormSheet extends StatelessWidget {
  final String title;
  final Widget child;
  final bool saving;
  final VoidCallback onSave;
  const _FormSheet({required this.title, required this.child, required this.saving, required this.onSave});

  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    padding: EdgeInsets.fromLTRB(20, 16, 20, MediaQuery.viewInsetsOf(context).bottom + 20),
    child: SafeArea(child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: AppColors.outline, borderRadius: BorderRadius.circular(2)))),
      const SizedBox(height: 16),
      Text(title, style: GoogleFonts.spaceGrotesk(fontSize: 20, fontWeight: FontWeight.w700)),
      const SizedBox(height: 16), child, const SizedBox(height: 8),
      SizedBox(height: 48, child: FilledButton(onPressed: saving ? null : onSave, child: saving ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save'))),
    ]))),
  );
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final bool required, number;
  final int lines;
  final String? errorText;
  const _Field({required this.controller, required this.label, this.required = false, this.number = false, this.lines = 1, this.errorText});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextFormField(
      controller: controller, maxLines: lines, keyboardType: number ? TextInputType.number : TextInputType.text,
      style: GoogleFonts.spaceGrotesk(),
      decoration: InputDecoration(labelText: label, errorText: errorText),
      validator: (value) {
        if (required && (value == null || value.trim().isEmpty)) return 'Required';
        if (number && value != null && value.isNotEmpty && (int.tryParse(value) == null || int.parse(value) < 0)) return 'Enter 0 or more';
        return null;
      },
    ),
  );
}

class _Dropdown extends StatelessWidget {
  final String label, value;
  final List<String> values;
  final ValueChanged<String> onChanged;
  final bool enabled;
  const _Dropdown({required this.label, required this.value, required this.values, required this.onChanged, this.enabled = true});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      initialValue: value, decoration: InputDecoration(labelText: label),
      items: values.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
      onChanged: enabled ? (v) { if (v != null) onChanged(v); } : null,
    ),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  final VoidCallback onTap;
  const _Card({required this.child, required this.onTap});
  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface, borderRadius: BorderRadius.circular(14),
    child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(14), child: Padding(padding: const EdgeInsets.all(14), child: child)),
  );
}

class _RemoteIcon extends StatelessWidget {
  final String url;
  final IconData fallback;
  const _RemoteIcon({required this.url, required this.fallback});
  @override
  Widget build(BuildContext context) => Container(
    width: 52, height: 52,
    decoration: BoxDecoration(color: AppColors.primaryContainer, borderRadius: BorderRadius.circular(12)),
    child: url.startsWith('http')
        ? Image.network(url, fit: BoxFit.contain, errorBuilder: (_, __, ___) => Icon(fallback, color: AppColors.primary))
        : Icon(fallback, color: AppColors.primary),
  );
}

class _Chip extends StatelessWidget {
  final String text;
  const _Chip(this.text);
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: AppColors.surfaceContainerLow, borderRadius: BorderRadius.circular(20)),
    child: Text(text, style: GoogleFonts.spaceGrotesk(fontSize: 11, color: AppColors.onSurfaceMuted)),
  );
}

class _MessageState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _MessageState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
    const Icon(Icons.cloud_off_outlined, size: 48, color: AppColors.onSurfaceMuted), const SizedBox(height: 12),
    Text(message, textAlign: TextAlign.center, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)), const SizedBox(height: 12),
    SizedBox(height: 44, child: OutlinedButton(onPressed: onRetry, child: const Text('Try again'))),
  ])));
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String text;
  const _EmptyState({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 52, color: AppColors.onSurfaceMuted), const SizedBox(height: 12),
    Text(text, style: GoogleFonts.spaceGrotesk(color: AppColors.onSurfaceMuted)),
  ]));
}
