import 'package:flutter/foundation.dart';

/// Logging levels for the application
enum LogLevel {
  debug,
  info,
  warn,
  error,
}

/// App-wide logger utility
/// Replaces print statements with structured logging
class AppLogger {
  static LogLevel _minLevel = kDebugMode ? LogLevel.debug : LogLevel.info;

  /// Set minimum log level (default: debug in dev, info in release)
  static void setMinLevel(LogLevel level) {
    _minLevel = level;
  }

  /// Log debug message (development only)
  static void debug(String tag, String message) {
    _log(LogLevel.debug, tag, message);
  }

  /// Log info message
  static void info(String tag, String message) {
    _log(LogLevel.info, tag, message);
  }

  /// Log warning message
  static void warn(String tag, String message) {
    _log(LogLevel.warn, tag, message);
  }

  /// Log error message with optional exception
  static void error(String tag, String message, [Object? error, StackTrace? stackTrace]) {
    _log(LogLevel.error, tag, message);
    if (error != null && kDebugMode) {
      debugPrint('  Exception: $error');
      if (stackTrace != null) {
        debugPrint('  StackTrace: $stackTrace');
      }
    }
  }

  /// Internal log method
  static void _log(LogLevel level, String tag, String message) {
    if (level.index < _minLevel.index) return;

    final prefix = _getPrefix(level);
    final timestamp = DateTime.now().toIso8601String().substring(11, 23);
    
    // Use debugPrint which handles long messages better than print
    debugPrint('$prefix [$timestamp] [$tag] $message');
  }

  static String _getPrefix(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return '[DEBUG]';
      case LogLevel.info:
        return '[INFO]';
      case LogLevel.warn:
        return '[WARN]';
      case LogLevel.error:
        return '[ERROR]';
    }
  }
}

/// Shorthand logging methods for common use
/// Supports both 1 and 2 argument calls
void logDebug(String tagOrMessage, [String? message]) {
  if (message != null) {
    AppLogger.debug(tagOrMessage, message);
  } else {
    // Parse [Tag] from message if present
    final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(tagOrMessage);
    if (match != null) {
      AppLogger.debug(match.group(1)!, match.group(2) ?? '');
    } else {
      AppLogger.debug('App', tagOrMessage);
    }
  }
}

void logInfo(String tagOrMessage, [String? message]) {
  if (message != null) {
    AppLogger.info(tagOrMessage, message);
  } else {
    final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(tagOrMessage);
    if (match != null) {
      AppLogger.info(match.group(1)!, match.group(2) ?? '');
    } else {
      AppLogger.info('App', tagOrMessage);
    }
  }
}

void logWarn(String tagOrMessage, [String? message]) {
  if (message != null) {
    AppLogger.warn(tagOrMessage, message);
  } else {
    final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(tagOrMessage);
    if (match != null) {
      AppLogger.warn(match.group(1)!, match.group(2) ?? '');
    } else {
      AppLogger.warn('App', tagOrMessage);
    }
  }
}

void logError(String tagOrMessage, [String? messageOrError, Object? error, StackTrace? stackTrace]) {
  if (messageOrError is String && messageOrError.isNotEmpty && !messageOrError.startsWith('[')) {
    AppLogger.error(tagOrMessage, messageOrError, error, stackTrace);
  } else {
    final match = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(tagOrMessage);
    if (match != null) {
      AppLogger.error(match.group(1)!, match.group(2) ?? '', messageOrError, error as StackTrace?);
    } else {
      AppLogger.error('App', tagOrMessage, messageOrError, error as StackTrace?);
    }
  }
}
