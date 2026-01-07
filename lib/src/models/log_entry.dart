import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

enum LogLevel {
  info,
  success,
  warning,
  error,
}

class LogEntry {
  final String message;
  final LogLevel level;
  final DateTime timestamp;

  LogEntry({
    required this.message,
    required this.level,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Get the color associated with this log level
  Color get color {
    switch (level) {
      case LogLevel.info:
        return Colors.white;
      case LogLevel.success:
        return Colors.green;
      case LogLevel.warning:
        return Colors.yellow.shade700;
      case LogLevel.error:
        return Colors.red;
    }
  }

  /// Format the timestamp in human-readable format (HH:mm:ss)
  String get formattedTimestamp {
    final formatter = DateFormat('HH:mm:ss');
    return formatter.format(timestamp);
  }

  /// Get the full log line with timestamp
  String get fullLogLine {
    return '[$formattedTimestamp] $message';
  }
}
