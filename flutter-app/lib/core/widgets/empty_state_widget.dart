import 'package:flutter/material.dart';

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
                color: iconColor ?? (isDark ? Colors.grey[400] : Colors.grey[600]),
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
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  /// Factory for empty course list
  factory EmptyStateWidget.courses({VoidCallback? onExplore}) {
    return EmptyStateWidget(
      icon: Icons.school_outlined,
      title: 'No Courses Yet',
      description: 'Start your learning journey by exploring our courses.',
      actionLabel: onExplore != null ? 'Explore Courses' : null,
      onAction: onExplore,
      iconColor: Colors.blue,
    );
  }
  
  /// Factory for empty vocabulary
  factory EmptyStateWidget.vocabulary({VoidCallback? onAdd}) {
    return EmptyStateWidget(
      icon: Icons.library_books_outlined,
      title: 'No Vocabulary',
      description: 'Add words to build your vocabulary library.',
      actionLabel: onAdd != null ? 'Add Words' : null,
      onAction: onAdd,
      iconColor: Colors.green,
    );
  }
  
  /// Factory for empty notifications
  factory EmptyStateWidget.notifications() {
    return const EmptyStateWidget(
      icon: Icons.notifications_none_outlined,
      title: 'No Notifications',
      description: 'You\'re all caught up! Check back later.',
      iconColor: Colors.orange,
    );
  }
  
  /// Factory for empty chat history
  factory EmptyStateWidget.chatHistory({VoidCallback? onStartChat}) {
    return EmptyStateWidget(
      icon: Icons.chat_bubble_outline,
      title: 'No Conversations',
      description: 'Start a conversation with our AI tutor.',
      actionLabel: onStartChat != null ? 'Start Chat' : null,
      onAction: onStartChat,
      iconColor: Colors.purple,
    );
  }
  
  /// Factory for empty search results
  factory EmptyStateWidget.searchResults({String? query}) {
    return EmptyStateWidget(
      icon: Icons.search_off,
      title: 'No Results Found',
      description: query != null 
          ? 'No results found for "$query". Try a different search term.'
          : 'No results found. Try a different search term.',
      iconColor: Colors.grey,
    );
  }
  
  /// Factory for empty progress
  factory EmptyStateWidget.progress({VoidCallback? onStart}) {
    return EmptyStateWidget(
      icon: Icons.trending_up_outlined,
      title: 'No Progress Yet',
      description: 'Complete lessons to track your learning progress.',
      actionLabel: onStart != null ? 'Start Learning' : null,
      onAction: onStart,
      iconColor: Colors.teal,
    );
  }
  
  /// Factory for network error
  factory EmptyStateWidget.networkError({VoidCallback? onRetry}) {
    return EmptyStateWidget(
      icon: Icons.wifi_off_outlined,
      title: 'No Internet Connection',
      description: 'Please check your network and try again.',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      iconColor: Colors.red,
    );
  }
  
  /// Factory for server error
  factory EmptyStateWidget.serverError({VoidCallback? onRetry}) {
    return EmptyStateWidget(
      icon: Icons.cloud_off_outlined,
      title: 'Something Went Wrong',
      description: 'We\'re having trouble connecting. Please try again.',
      actionLabel: onRetry != null ? 'Retry' : null,
      onAction: onRetry,
      iconColor: Colors.red,
    );
  }
}
