import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/features/onboarding/domain/entities/start_learning_target.dart';
import 'package:lexilingo_app/features/onboarding/presentation/providers/start_learning_provider.dart';
import 'package:provider/provider.dart';

/// Calls start-learning as soon as it opens, then hands the first lesson to
/// [onStarted]. A failure keeps the learner here with a retry and a way out.
class StartLearningPage extends StatefulWidget {
  final String? courseId;
  final ValueChanged<StartLearningTarget> onStarted;
  final VoidCallback onSkip;

  const StartLearningPage({
    super.key,
    this.courseId,
    required this.onStarted,
    required this.onSkip,
  });

  @override
  State<StartLearningPage> createState() => _StartLearningPageState();
}

class _StartLearningPageState extends State<StartLearningPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    if (!mounted) return;
    final target = await context.read<StartLearningProvider>().start(
      courseId: widget.courseId,
    );
    if (!mounted || target == null) return;
    widget.onStarted(target);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final failed =
        context.watch<StartLearningProvider>().status ==
        StartLearningStatus.failed;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: failed ? _buildError(theme) : _buildLoading(theme),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const CircularProgressIndicator(),
        const SizedBox(height: 24),
        Text(
          'onboarding.startingTitle'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'onboarding.startingSubtitle'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildError(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Icon(
          Icons.error_outline_rounded,
          size: 48,
          color: theme.colorScheme.error,
        ),
        const SizedBox(height: 16),
        Text(
          'onboarding.startFailedTitle'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'onboarding.startFailedBody'.tr(),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: _run,
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text('common.retry'.tr()),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: widget.onSkip,
          style: TextButton.styleFrom(minimumSize: const Size.fromHeight(48)),
          child: Text('onboarding.goHome'.tr()),
        ),
      ],
    );
  }
}
