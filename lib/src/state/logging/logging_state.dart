import 'package:flutter/material.dart' show Color, Colors;

enum LogLevel {
  info,
  warning,
  error,
  debug,
  network,
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? category;
  final Map<String, dynamic>? metadata;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.category,
    this.metadata,
  });

  Color get color {
    switch (level) {
      case LogLevel.info:
        return Colors.white;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Colors.red;
      case LogLevel.debug:
        return Colors.grey;
      case LogLevel.network:
        return Colors.blue;
    }
  }

  String get levelText {
    switch (level) {
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.network:
        return 'NET';
    }
  }

  String get formattedTime {
    return '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
  }

  @override
  String toString() {
    final cat = category != null ? '[$category] ' : '';
    return '$formattedTime [$levelText] $cat$message';
  }
}

class LoggingState {
  final List<LogEntry> entries;
  final bool isVisible;
  final Set<LogLevel> visibleLevels;
  final String? filterText;
  final int maxEntries;

  const LoggingState({
    this.entries = const [],
    this.isVisible = false,
    this.visibleLevels = const {
      LogLevel.info,
      LogLevel.warning,
      LogLevel.error,
      LogLevel.network,
    },
    this.filterText,
    this.maxEntries = 1000,
  });

  LoggingState copyWith({
    List<LogEntry>? entries,
    bool? isVisible,
    Set<LogLevel>? visibleLevels,
    String? filterText,
    int? maxEntries,
  }) {
    return LoggingState(
      entries: entries ?? this.entries,
      isVisible: isVisible ?? this.isVisible,
      visibleLevels: visibleLevels ?? this.visibleLevels,
      filterText: filterText ?? this.filterText,
      maxEntries: maxEntries ?? this.maxEntries,
    );
  }

  List<LogEntry> get filteredEntries {
    var filtered = entries.where((entry) => visibleLevels.contains(entry.level));

    if (filterText != null && filterText!.isNotEmpty) {
      final filter = filterText!.toLowerCase();
      filtered = filtered.where((entry) =>
          entry.message.toLowerCase().contains(filter) ||
          (entry.category?.toLowerCase().contains(filter) ?? false));
    }

    return filtered.toList();
  }
}
