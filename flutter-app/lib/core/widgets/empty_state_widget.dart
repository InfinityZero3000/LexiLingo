import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Shared empty/error state: optional mark, title, description, one action.
class EmptyStateWidget extends StatefulWidget {
  final IconData? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.iconSize = 56,
  });

  @override
  State<EmptyStateWidget> createState() => _EmptyStateWidgetState();

  /// Factory for empty course list
  factory EmptyStateWidget.courses() {
    return EmptyStateWidget(
      icon: Icons.school_outlined,
      title: 'emptyState.noCourses'.tr(),
      description: 'emptyState.noCoursesDesc'.tr(),
      iconColor: Colors.blue,
    );
  }

  /// Factory for empty vocabulary
  factory EmptyStateWidget.vocabulary({VoidCallback? onAdd}) {
    return EmptyStateWidget(
      icon: Icons.library_books_outlined,
      title: 'emptyState.noVocabulary'.tr(),
      description: 'emptyState.noVocabularyDesc'.tr(),
      actionLabel: onAdd != null ? 'emptyState.addWords'.tr() : null,
      onAction: onAdd,
      iconColor: AppColors.greenSuccessBright,
    );
  }

  /// Factory for empty notifications
  factory EmptyStateWidget.notifications() {
    return EmptyStateWidget(
      icon: Icons.notifications_none_outlined,
      title: 'notifications.emptyTitle'.tr(),
      description: 'emptyState.allCaughtUp'.tr(),
      iconColor: AppColors.orange,
    );
  }

  /// Factory for empty chat history
  factory EmptyStateWidget.chatHistory({VoidCallback? onStartChat}) {
    return EmptyStateWidget(
      icon: Icons.chat_bubble_outline,
      title: 'emptyState.noConversations'.tr(),
      description: 'emptyState.noConversationsDesc'.tr(),
      actionLabel: onStartChat != null ? 'emptyState.startChat'.tr() : null,
      onAction: onStartChat,
      iconColor: AppColors.purple,
    );
  }

  /// Factory for empty search results
  factory EmptyStateWidget.searchResults({String? query}) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'emptyState.noResults'.tr(),
      description: query != null
          ? 'emptyState.noResultsForQuery'.tr(namedArgs: {'query': query})
          : 'emptyState.noResultsDesc'.tr(),
      iconColor: Colors.grey,
    );
  }

  /// Factory for empty progress
  factory EmptyStateWidget.progress({VoidCallback? onStart}) {
    return EmptyStateWidget(
      icon: Icons.trending_up_outlined,
      title: 'emptyState.noProgress'.tr(),
      description: 'emptyState.noProgressDesc'.tr(),
      actionLabel: onStart != null ? 'course.startLearning'.tr() : null,
      onAction: onStart,
      iconColor: AppColors.teal,
    );
  }

  /// Factory for network error
  factory EmptyStateWidget.networkError({VoidCallback? onRetry}) {
    return EmptyStateWidget(
      icon: Icons.wifi_off_outlined,
      title: 'errors.noInternet'.tr(),
      description: 'emptyState.noInternetDesc'.tr(),
      actionLabel: onRetry != null ? 'common.retry'.tr() : null,
      onAction: onRetry,
      iconColor: AppColors.errorBright,
    );
  }

  /// Factory for server error
  factory EmptyStateWidget.serverError({VoidCallback? onRetry}) {
    return EmptyStateWidget(
      icon: Icons.cloud_off_outlined,
      title: 'notifications.somethingWentWrong'.tr(),
      description: 'emptyState.serverErrorDesc'.tr(),
      actionLabel: onRetry != null ? 'common.retry'.tr() : null,
      onAction: onRetry,
      iconColor: AppColors.errorBright,
    );
  }
}

class _EmptyStateWidgetState extends State<EmptyStateWidget>
    with SingleTickerProviderStateMixin {
  // One run, then rest: the mark settles in, echoes twice, and stops. A loop
  // would nag on a screen the learner may sit on, and never lets tests settle.
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2600),
  );
  late final Animation<double> _mark = _interval(0, 0.24);
  late final Animation<double> _text = _interval(0.05, 0.29);
  late final Animation<double> _action = _interval(0.11, 0.35);
  bool _started = false;

  Animation<double> _interval(double begin, double end) => CurvedAnimation(
    parent: _controller,
    curve: Interval(begin, end, curve: Curves.easeOutExpo),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _rise(Animation<double> animation, Widget child) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(
        begin: const Offset(0, 0.3),
        end: Offset.zero,
      ).animate(animation),
      child: child,
    ),
  );

  Widget _buildMark(Color accent, Color muted) {
    final tile = widget.iconSize + 40;
    return SizedBox.square(
      dimension: tile,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _controller,
              builder: (context, _) {
                final t = _controller.value;
                if (t <= 0.2 || t >= 1) return const SizedBox.shrink();
                final phase = ((t - 0.2) / 0.8 * 2) % 1;
                return Transform.scale(
                  scale: 1 + 0.5 * Curves.easeOutCubic.transform(phase),
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: accent.withValues(alpha: 0.3 * (1 - phase)),
                        width: 2,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(
            child: FadeTransition(
              opacity: _mark,
              child: ScaleTransition(
                scale: Tween(begin: 0.82, end: 1.0).animate(_mark),
                child: Container(
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    widget.icon,
                    size: widget.iconSize,
                    color: widget.iconColor ?? muted,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final accent = widget.iconColor ?? theme.colorScheme.primary;
    final hasAction = widget.actionLabel != null && widget.onAction != null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.icon != null) ...[
              _buildMark(accent, muted),
              const SizedBox(height: 24),
            ],
            _rise(
              _text,
              Column(
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      widget.description!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: muted,
                        height: 1.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            if (hasAction) ...[
              const SizedBox(height: 24),
              _rise(
                _action,
                ElevatedButton(
                  onPressed: widget.onAction,
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(0, 48),
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                  ),
                  child: Text(widget.actionLabel!),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
