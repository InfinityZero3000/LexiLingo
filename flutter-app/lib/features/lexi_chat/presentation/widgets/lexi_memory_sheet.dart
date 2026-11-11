import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/lexi_chat/domain/repositories/lexi_chat_repository.dart';
import 'package:lexilingo_app/features/lexi_chat/presentation/providers/lexi_memory_provider.dart';
import 'package:provider/provider.dart';

/// Bottom sheet listing what Lexi remembers from chat, with a way to forget it.
class LexiMemorySheet extends StatelessWidget {
  const LexiMemorySheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => ChangeNotifierProvider(
        create: (_) =>
            LexiMemoryProvider(repository: sl<LexiChatRepository>())..load(),
        child: const LexiMemorySheet(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final provider = context.watch<LexiMemoryProvider>();

    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'lexiChat.memory.title'.tr(),
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'lexiChat.memory.subtitle'.tr(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 16),
            Flexible(child: _Body(provider: provider)),
          ],
        ),
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final LexiMemoryProvider provider;

  const _Body({required this.provider});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    switch (provider.status) {
      case LexiMemoryStatus.loading:
        return const Padding(
          padding: EdgeInsets.symmetric(vertical: 32),
          child: Center(child: CircularProgressIndicator()),
        );
      case LexiMemoryStatus.failed:
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            children: [
              Text(
                'lexiChat.memory.loadFailed'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: provider.load,
                child: Text('lexiChat.memory.retry'.tr()),
              ),
            ],
          ),
        );
      case LexiMemoryStatus.ready:
        final facts = provider.facts;
        if (facts.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Text(
                'lexiChat.memory.empty'.tr(),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: facts.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: theme.colorScheme.outlineVariant),
                itemBuilder: (context, index) {
                  final fact = facts[index];
                  return _FactRow(
                    label: 'lexiChat.memory.key.${fact.key}'.tr(),
                    value: fact.value,
                    onForget: () => _forgetOne(context, fact.key),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: () => _confirmForgetAll(context),
                style: TextButton.styleFrom(
                  foregroundColor: theme.colorScheme.error,
                  minimumSize: const Size(48, 48),
                ),
                icon: const Icon(Icons.delete_sweep_rounded),
                label: Text('lexiChat.memory.forgetAll'.tr()),
              ),
            ),
          ],
        );
    }
  }

  Future<void> _forgetOne(BuildContext context, String key) async {
    final ok = await provider.forget(key);
    if (!ok && context.mounted) _showFailure(context);
  }

  Future<void> _confirmForgetAll(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('lexiChat.memory.confirmTitle'.tr()),
        content: Text('lexiChat.memory.confirmBody'.tr()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text('lexiChat.memory.cancel'.tr()),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            child: Text('lexiChat.memory.forgetAll'.tr()),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await provider.forgetAll();
    if (!ok && context.mounted) _showFailure(context);
  }

  void _showFailure(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('lexiChat.memory.actionFailed'.tr())),
    );
  }
}

class _FactRow extends StatelessWidget {
  final String label;
  final String value;
  final VoidCallback onForget;

  const _FactRow({
    required this.label,
    required this.value,
    required this.onForget,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                Text(value, style: theme.textTheme.bodyLarge),
              ],
            ),
          ),
          IconButton(
            onPressed: onForget,
            tooltip: 'lexiChat.memory.forgetOne'.tr(),
            constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: Icon(
              Icons.close_rounded,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
