import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:lexilingo_app/core/di/service_locator.dart';
import 'package:lexilingo_app/features/notifications/domain/services/push_permission_gateway.dart';
import 'package:lexilingo_app/features/notifications/presentation/providers/push_permission_provider.dart';
import 'package:lexilingo_app/core/theme/app_tokens.dart';

class PushPermissionCard extends StatelessWidget {
  final PushPermissionGateway? gateway;

  const PushPermissionCard({super.key, this.gateway});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<PushPermissionProvider>(
      create: (_) => PushPermissionProvider(
        gateway: gateway ?? sl<PushPermissionGateway>(),
      )..evaluate(),
      child: const _PushPermissionBody(),
    );
  }
}

class _PushPermissionBody extends StatelessWidget {
  const _PushPermissionBody();

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PushPermissionProvider>();
    if (!provider.visible) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'lesson.pushPrompt'.tr(),
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  style: TextButton.styleFrom(minimumSize: const Size(44, 44)),
                  onPressed: provider.busy ? null : provider.notNow,
                  child: Text('lesson.pushPromptLater'.tr()),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(44, 44),
                  ),
                  onPressed: provider.busy ? null : provider.allow,
                  child: Text('lesson.pushPromptAllow'.tr()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
