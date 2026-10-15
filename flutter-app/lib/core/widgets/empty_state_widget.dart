import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:lexilingo_app/core/theme/app_theme.dart';

/// Reusable empty state widget with illustration and action button
class EmptyStateWidget extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color? iconColor;
  final double iconSize;

  const EmptyStateWidget({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    this.iconColor,
    this.iconSize = 80,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: (iconColor ?? theme.primaryColor).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: iconSize,
                color:
                    iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (description != null) ...[
              const SizedBox(height: 12),
              Text(
                description!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add),
                label: Text(actionLabel!),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

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
