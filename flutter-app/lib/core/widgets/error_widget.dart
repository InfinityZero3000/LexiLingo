import 'package:flutter/material.dart';

/// Types of errors that can be displayed
enum ErrorType {
  network,
  server,
  timeout,
  unauthorized,
  notFound,
  unknown,
}

/// Reusable error widget with retry functionality
class ErrorDisplayWidget extends StatelessWidget {
  final ErrorType errorType;
  final String? customMessage;
  final VoidCallback? onRetry;
  final bool compact;
  
  const ErrorDisplayWidget({
    super.key,
    this.errorType = ErrorType.unknown,
    this.customMessage,
    this.onRetry,
    this.compact = false,
  });
  
  /// Create from exception/failure message
  factory ErrorDisplayWidget.fromMessage({
    required String message,
    VoidCallback? onRetry,
    bool compact = false,
  }) {
    final errorType = _parseErrorType(message);
    return ErrorDisplayWidget(
      errorType: errorType,
      customMessage: message,
      onRetry: onRetry,
      compact: compact,
    );
  }
  
  static ErrorType _parseErrorType(String message) {
    final lower = message.toLowerCase();
    if (lower.contains('network') || lower.contains('connection') || lower.contains('internet')) {
      return ErrorType.network;
    }
    if (lower.contains('timeout')) {
      return ErrorType.timeout;
    }
    if (lower.contains('unauthorized') || lower.contains('401')) {
      return ErrorType.unauthorized;
    }
    if (lower.contains('not found') || lower.contains('404')) {
      return ErrorType.notFound;
    }
    if (lower.contains('server') || lower.contains('500')) {
      return ErrorType.server;
    }
    return ErrorType.unknown;
  }
  
  IconData get _icon {
    switch (errorType) {
      case ErrorType.network:
        return Icons.wifi_off_rounded;
      case ErrorType.server:
        return Icons.cloud_off_rounded;
      case ErrorType.timeout:
        return Icons.timer_off_rounded;
      case ErrorType.unauthorized:
        return Icons.lock_outline_rounded;
      case ErrorType.notFound:
        return Icons.search_off_rounded;
      case ErrorType.unknown:
        return Icons.error_outline_rounded;
    }
  }
  
  Color get _iconColor {
    switch (errorType) {
      case ErrorType.network:
      case ErrorType.timeout:
        return Colors.orange;
      case ErrorType.server:
      case ErrorType.unknown:
        return Colors.red;
      case ErrorType.unauthorized:
        return Colors.amber;
      case ErrorType.notFound:
        return Colors.grey;
    }
  }
  
  String get _title {
    switch (errorType) {
      case ErrorType.network:
        return 'No Internet Connection';
      case ErrorType.server:
        return 'Server Error';
      case ErrorType.timeout:
        return 'Request Timeout';
      case ErrorType.unauthorized:
        return 'Session Expired';
      case ErrorType.notFound:
        return 'Not Found';
      case ErrorType.unknown:
        return 'Something Went Wrong';
    }
  }
  
  String get _description {
    switch (errorType) {
      case ErrorType.network:
        return 'Please check your internet connection and try again.';
      case ErrorType.server:
        return 'Our servers are having trouble. Please try again later.';
      case ErrorType.timeout:
        return 'The request took too long. Please try again.';
      case ErrorType.unauthorized:
        return 'Please log in again to continue.';
      case ErrorType.notFound:
        return 'The requested content could not be found.';
      case ErrorType.unknown:
        return customMessage ?? 'An unexpected error occurred. Please try again.';
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (compact) {
      return _buildCompact(context);
    }
    return _buildFull(context);
  }
  
  Widget _buildCompact(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _iconColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _iconColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(_icon, color: _iconColor, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              _title,
              style: TextStyle(
                color: _iconColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (onRetry != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              color: _iconColor,
              onPressed: onRetry,
              tooltip: 'Retry',
            ),
        ],
      ),
    );
  }
  
  Widget _buildFull(BuildContext context) {
    final theme = Theme.of(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _icon,
                size: 64,
                color: _iconColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              _description,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _iconColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                ),
              ),
            ],
            if (errorType == ErrorType.unauthorized) ...[
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  // Navigate to login
                  Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
                },
                child: const Text('Go to Login'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Offline indicator banner
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  
  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      color: Colors.orange.shade800,
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Text(
            'You are offline',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
