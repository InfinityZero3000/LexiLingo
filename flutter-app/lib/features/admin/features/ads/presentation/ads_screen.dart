import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';
import '../../../core/network/admin_api_error.dart';
import '../../../core/permissions/admin_permissions.dart';
import '../../../shared/widgets/admin_shell.dart';
import '../../../shared/widgets/growth_form.dart';
import '../../../shared/widgets/growth_state_body.dart';
import '../data/banner_repository.dart';
import 'package:provider/provider.dart';

const _kPositions = ['hero', 'sidebar', 'interstitial'];
const _kLevels = ['Any', 'A1', 'A2', 'B1', 'B2', 'C1', 'C2'];

class AdsScreen extends StatefulWidget {
  const AdsScreen({super.key, this.repository});

  final BannerRepository? repository;

  @override
  State<AdsScreen> createState() => _AdsScreenState();
}

class _AdsScreenState extends State<AdsScreen> {
  late final BannerRepository _repo = widget.repository ?? BannerRepository();
  List<BannerItem> _banners = const [];
  bool _loading = true;
  Object? _error;

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
      setState(() => _banners = banners);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _write(Future<void> Function() action, String failKey) async {
    try {
      await action();
      await _load();
    } catch (e) {
      final api = AdminApiError.from(e);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(api.isForbidden ? api.message.resolve() : failKey.tr()),
        ),
      );
    }
  }

  final _toggling = <String>{};

  Future<void> _toggle(BannerItem item) async {
    if (!_toggling.add(item.id)) return;
    final next = !item.isActive;
    _setActive(item.id, next);
    try {
      await _repo.setActive(item.id, next);
    } catch (e) {
      _setActive(item.id, !next);
      final api = AdminApiError.from(e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              api.isForbidden
                  ? api.message.resolve()
                  : 'adminGrowth.common.updateFailed'.tr(),
            ),
          ),
        );
      }
    } finally {
      _toggling.remove(item.id);
    }
  }

  void _setActive(String id, bool active) {
    if (!mounted) return;
    setState(() {
      _banners = [
        for (final b in _banners) b.id == id ? b.copyWith(isActive: active) : b,
      ];
    });
  }

  Future<void> _form([BannerItem? item]) async {
    final payload = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => BannerForm(item: item),
    );
    if (payload == null) return;
    await _write(
      () => item == null
          ? _repo.createBanner(payload)
          : _repo.updateBanner(item.id, payload),
      'adminGrowth.common.saveFailed',
    );
  }

  @override
  Widget build(BuildContext context) {
    final perms = context.watch<AdminPermissions>();
    final canCreate = perms.can('banners:create');
    final canUpdate = perms.can('banners:update');
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
          icon: const Icon(Icons.menu_rounded),
          onPressed: AdminShell.openDrawer,
        ),
        title: Text('adminGrowth.ads.title'.tr()),
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => _form(),
              icon: const Icon(Icons.add),
              label: Text('adminGrowth.ads.create'.tr()),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: _load,
        child: GrowthStateBody(
          isLoading: _loading,
          hasData: _banners.isNotEmpty,
          error: _error,
          onRetry: _load,
          emptyTitleKey: 'adminGrowth.ads.empty',
          emptyIcon: Icons.campaign_outlined,
          builder: (_) => ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              96,
            ),
            children: [
              for (final b in _banners)
                BannerCard(
                  item: b,
                  onEdit: canUpdate ? () => _form(b) : null,
                  onToggle: canUpdate ? () => _toggle(b) : null,
                ),
              const GrowthWebOnlyNote(),
            ],
          ),
        ),
      ),
    );
  }
}

class BannerCard extends StatelessWidget {
  const BannerCard({super.key, required this.item, this.onEdit, this.onToggle});

  final BannerItem item;
  final VoidCallback? onEdit;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final level = item.targetMinLevel == null && item.targetMaxLevel == null
        ? 'adminGrowth.ads.anyLevel'.tr()
        : '${item.targetMinLevel ?? 'A1'}–${item.targetMaxLevel ?? 'C2'}';
    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.md),
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: AppRadius.lgAll,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  item.title,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Semantics(
                label: 'adminGrowth.common.active'.tr(),
                child: Switch(
                  value: item.isActive,
                  onChanged: onToggle == null ? null : (_) => onToggle!(),
                ),
              ),
            ],
          ),
          if (item.description?.isNotEmpty == true)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                item.description!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.sm),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs + 2,
            children: [
              GrowthChip(item.position),
              GrowthChip(
                'adminGrowth.ads.priorityChip'.tr(
                  args: [('${item.priority}').toString()],
                ),
              ),
              GrowthChip(
                item.targetLanguage ?? 'adminGrowth.ads.anyLanguage'.tr(),
              ),
              GrowthChip(level),
            ],
          ),
          if (onEdit != null)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                constraints: const BoxConstraints(
                  minWidth: kMinTapTarget,
                  minHeight: kMinTapTarget,
                ),
                tooltip: 'adminGrowth.common.edit'.tr(),
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

class BannerForm extends StatefulWidget {
  const BannerForm({super.key, this.item});
  final BannerItem? item;

  @override
  State<BannerForm> createState() => _BannerFormState();
}

class _BannerFormState extends State<BannerForm> {
  late final TextEditingController title,
      description,
      imageUrl,
      linkUrl,
      priority,
      targetLanguage;
  late String position, minLevel, maxLevel;
  late bool active;
  DateTime? startAt, endAt;
  String? _problem;

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

  @override
  void dispose() {
    for (final c in [
      title,
      description,
      imageUrl,
      linkUrl,
      priority,
      targetLanguage,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(bool isStart) async {
    final current = (isStart ? startAt : endAt) ?? DateTime.now();
    final firstDate = DateTime(2020);
    final picked = await showDatePicker(
      context: context,
      initialDate: current.isBefore(firstDate) ? firstDate : current,
      firstDate: firstDate,
      lastDate: DateTime(2100),
    );
    if (picked == null || !mounted) return;
    setState(() => isStart ? startAt = picked : endAt = picked);
  }

  String _fmt(DateTime? d) => d == null
      ? 'adminGrowth.ads.unlimited'.tr()
      : '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String? _blankToNull(TextEditingController c) =>
      c.text.trim().isEmpty ? null : c.text.trim();

  void _save() {
    final lo = _kLevels.indexOf(minLevel);
    final hi = _kLevels.indexOf(maxLevel);
    final String? problem;
    if (title.text.trim().isEmpty || imageUrl.text.trim().isEmpty) {
      problem = 'adminGrowth.ads.needTitleImage'.tr();
    } else if (startAt != null && endAt != null && endAt!.isBefore(startAt!)) {
      problem = 'adminGrowth.ads.endBeforeStart'.tr();
    } else if (lo > 0 && hi > 0 && lo > hi) {
      problem = 'adminGrowth.ads.minAboveMax'.tr();
    } else {
      problem = null;
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(context, {
      'title': title.text.trim(),
      'description': _blankToNull(description),
      'image_url': imageUrl.text.trim(),
      'link_url': _blankToNull(linkUrl),
      'position': position,
      'priority': int.tryParse(priority.text) ?? 0,
      'is_active': active,
      'start_at': startAt?.toUtc().toIso8601String(),
      'end_at': endAt?.toUtc().toIso8601String(),
      'target_min_level': minLevel == 'Any' ? null : minLevel,
      'target_max_level': maxLevel == 'Any' ? null : maxLevel,
      'target_language': _blankToNull(targetLanguage),
    });
  }

  @override
  Widget build(BuildContext context) {
    String level(String v) => v == 'Any' ? 'adminGrowth.ads.levelAny'.tr() : v;
    return GrowthFormSheet(
      title: widget.item == null
          ? 'adminGrowth.ads.create'.tr()
          : 'adminGrowth.ads.edit'.tr(),
      onSave: _save,
      children: [
        GrowthField(
          controller: title,
          label: 'adminGrowth.ads.fieldTitle'.tr(),
        ),
        GrowthField(
          controller: description,
          label: 'adminGrowth.ads.fieldDescription'.tr(),
          lines: 2,
        ),
        GrowthField(
          controller: imageUrl,
          label: 'adminGrowth.ads.fieldImage'.tr(),
        ),
        GrowthField(
          controller: linkUrl,
          label: 'adminGrowth.ads.fieldLink'.tr(),
        ),
        GrowthDropdown(
          label: 'adminGrowth.ads.fieldPosition'.tr(),
          value: position,
          options: _kPositions,
          onChanged: (v) => setState(() => position = v),
        ),
        GrowthField(
          controller: priority,
          label: 'adminGrowth.ads.fieldPriority'.tr(),
          number: true,
        ),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                ),
                onPressed: () => _pickDate(true),
                child: Text(
                  'adminGrowth.ads.from'.tr(args: [(_fmt(startAt)).toString()]),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(kMinTapTarget, kMinTapTarget),
                ),
                onPressed: () => _pickDate(false),
                child: Text(
                  'adminGrowth.ads.to'.tr(args: [(_fmt(endAt)).toString()]),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Expanded(
              child: GrowthDropdown(
                label: 'adminGrowth.ads.fieldMinLevel'.tr(),
                value: minLevel,
                options: _kLevels,
                optionLabel: level,
                onChanged: (v) => setState(() => minLevel = v),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: GrowthDropdown(
                label: 'adminGrowth.ads.fieldMaxLevel'.tr(),
                value: maxLevel,
                options: _kLevels,
                optionLabel: level,
                onChanged: (v) => setState(() => maxLevel = v),
              ),
            ),
          ],
        ),
        GrowthField(
          controller: targetLanguage,
          label: 'adminGrowth.ads.fieldLanguage'.tr(),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text('adminGrowth.common.active'.tr()),
          value: active,
          onChanged: (v) => setState(() => active = v),
        ),
        if (_problem != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: Text(
              _problem!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    );
  }
}
