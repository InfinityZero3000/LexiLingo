import 'dart:convert';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../shared/widgets/growth_form.dart';
import '../data/gamification_repository.dart';

const _types = [
  'streak_freeze',
  'double_xp',
  'hint_pack',
  'heart_refill',
  'avatar',
  'theme',
  'time_freeze',
  'extra_time',
  'skip_token',
  'reveal_hint',
  'translate_hint',
  'mistake_shield',
  'extra_heart',
  'lucky_clover',
  'score_multiplier',
  'pair_swap',
];

class ShopForm extends StatefulWidget {
  const ShopForm({super.key, this.item, required this.repository});

  final ShopItem? item;
  final GamificationRepository repository;

  @override
  State<ShopForm> createState() => _ShopFormState();
}

class _ShopFormState extends State<ShopForm> {
  late final TextEditingController _name,
      _description,
      _price,
      _stock,
      _icon,
      _effects;
  late String _type;
  late bool _available;
  bool _saving = false, _submitted = false;
  String? _effectsError;

  @override
  void initState() {
    super.initState();
    final i = widget.item;
    _name = TextEditingController(text: i?.name);
    _description = TextEditingController(text: i?.description);
    _price = TextEditingController(text: '${i?.priceGems ?? 50}');
    _stock = TextEditingController(text: i?.stock?.toString() ?? '');
    _icon = TextEditingController(text: i?.iconUrl);
    _effects = TextEditingController(
      text: const JsonEncoder.withIndent('  ').convert(i?.effects ?? {}),
    );
    _type = i != null && _types.contains(i.itemType)
        ? i.itemType
        : _types.first;
    _available = i == null || i.isAvailable;
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _stock, _icon, _effects]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _required(TextEditingController c) =>
      _submitted && c.text.trim().isEmpty
      ? 'adminGrowth.gamify.required'.tr()
      : null;

  Future<void> _save() async {
    setState(() => _submitted = true);
    final stockText = _stock.text.trim();
    if (_name.text.trim().isEmpty ||
        _description.text.trim().isEmpty ||
        int.tryParse(_price.text.trim()) == null ||
        (stockText.isNotEmpty && int.tryParse(stockText) == null)) {
      return;
    }
    dynamic effects;
    try {
      effects = jsonDecode(_effects.text.trim().isEmpty ? '{}' : _effects.text);
    } catch (_) {
      setState(() => _effectsError = 'adminGrowth.gamify.effectsInvalid'.tr());
      return;
    }
    if (effects is! Map) {
      setState(() => _effectsError = 'adminGrowth.gamify.effectsObject'.tr());
      return;
    }
    setState(() {
      _saving = true;
      _effectsError = null;
    });
    try {
      await widget.repository.saveShop(widget.item?.id, {
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'item_type': _type,
        'price_gems': int.parse(_price.text.trim()),
        'is_available': _available,
        'stock_quantity': stockText.isEmpty ? null : int.parse(stockText),
        'icon_url': _icon.text.trim().isEmpty ? null : _icon.text.trim(),
        'effects': effects,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      final api = AdminApiError.from(e);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            api.isForbidden
                ? api.message.resolve()
                : 'adminGrowth.common.saveFailed'.tr(),
          ),
        ),
      );
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => GrowthFormSheet(
    title: widget.item == null
        ? 'adminGrowth.gamify.newShop'.tr()
        : 'adminGrowth.gamify.editShop'.tr(),
    saving: _saving,
    onSave: _save,
    children: [
      IgnorePointer(
        ignoring: widget.item != null,
        child: Opacity(
          opacity: widget.item != null ? 0.6 : 1,
          child: GrowthDropdown(
            label: 'adminGrowth.gamify.itemType'.tr(),
            value: _type,
            options: _types,
            onChanged: (v) => setState(() => _type = v),
          ),
        ),
      ),
      GrowthField(
        controller: _name,
        label: 'adminGrowth.gamify.name'.tr(),
        errorText: _required(_name),
      ),
      GrowthField(
        controller: _description,
        label: 'adminGrowth.gamify.description'.tr(),
        lines: 2,
        errorText: _required(_description),
      ),
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: GrowthField(
              controller: _price,
              label: 'adminGrowth.gamify.price'.tr(),
              number: true,
              errorText: _submitted && int.tryParse(_price.text.trim()) == null
                  ? 'adminGrowth.gamify.badNumber'.tr()
                  : null,
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: GrowthField(
              controller: _stock,
              label: 'adminGrowth.gamify.stock'.tr(),
              number: true,
            ),
          ),
        ],
      ),
      GrowthField(controller: _icon, label: 'adminGrowth.gamify.iconUrl'.tr()),
      GrowthField(
        controller: _effects,
        label: 'adminGrowth.gamify.effects'.tr(),
        lines: 4,
        errorText: _effectsError,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text('adminGrowth.gamify.available'.tr()),
        value: _available,
        onChanged: (v) => setState(() => _available = v),
      ),
    ],
  );
}
