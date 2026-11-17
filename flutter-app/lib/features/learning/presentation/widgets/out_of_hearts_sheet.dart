import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum OutOfHeartsChoice { refilled, restart, leave }

Future<OutOfHeartsChoice?> showOutOfHeartsSheet(
  BuildContext context, {
  required int? refillPrice,
  required int gems,
  required Future<bool> Function() onRefill,
}) {
  return showModalBottomSheet<OutOfHeartsChoice>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => OutOfHeartsSheet(
      refillPrice: refillPrice,
      gems: gems,
      onRefill: onRefill,
    ),
  );
}

class OutOfHeartsSheet extends StatefulWidget {
  const OutOfHeartsSheet({
    super.key,
    required this.refillPrice,
    required this.gems,
    required this.onRefill,
  });

  /// Null when the shop catalog has no Heart Refill, which hides the option.
  final int? refillPrice;
  final int gems;
  final Future<bool> Function() onRefill;

  @override
  State<OutOfHeartsSheet> createState() => _OutOfHeartsSheetState();
}

class _OutOfHeartsSheetState extends State<OutOfHeartsSheet> {
  bool _busy = false;
  bool _failed = false;

  Future<void> _refill() async {
    setState(() {
      _busy = true;
      _failed = false;
    });
    var ok = false;
    try {
      ok = await widget.onRefill();
    } catch (_) {
      ok = false;
    }
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop(OutOfHeartsChoice.refilled);
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final price = widget.refillPrice;
    final canAfford = price != null && widget.gems >= price;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Icon(Icons.heart_broken_rounded, size: 48, color: scheme.error),
            const SizedBox(height: 16),
            Text(
              'lesson.outOfHeartsTitle'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'lesson.outOfHeartsMessage'.tr(),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            if (price != null) ...[
              FilledButton.icon(
                onPressed: canAfford && !_busy ? _refill : null,
                icon: _busy
                    ? SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: scheme.onPrimary,
                        ),
                      )
                    : const Icon(Icons.favorite_rounded),
                label: Text(
                  'lesson.refillHearts'.tr(namedArgs: {'price': '$price'}),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
              ),
              if (!canAfford)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'lesson.refillNotEnoughGems'.tr(
                      namedArgs: {'price': '$price', 'gems': '${widget.gems}'},
                    ),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              if (_failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    'lesson.refillFailed'.tr(),
                    key: const Key('refill_error'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 12),
            ],
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pop(OutOfHeartsChoice.restart),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text('lesson.tryLessonAgain'.tr()),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => Navigator.of(context).pop(OutOfHeartsChoice.leave),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text('lesson.leaveLesson'.tr()),
            ),
          ],
        ),
      ),
    );
  }
}
