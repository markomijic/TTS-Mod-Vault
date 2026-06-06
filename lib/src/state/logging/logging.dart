import 'package:flutter/material.dart' show debugPrint;
import 'package:hooks_riverpod/hooks_riverpod.dart' show Ref, StateNotifier;
import 'package:tts_mod_vault/src/state/logging/logging_state.dart'
    show LogEntry, LogLevel, LoggingState;

class LoggingNotifier extends StateNotifier<LoggingState> {
  final Ref ref;

  LoggingNotifier(this.ref) : super(const LoggingState());

  void addLog(LogLevel level, String message, {String? category, Map<String, dynamic>? metadata}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      category: category,
      metadata: metadata,
    );

    // Also print to debug console
    debugPrint(entry.toString());

    // Add to state and maintain max entries limit
    final newEntries = [...state.entries, entry];
    if (newEntries.length > state.maxEntries) {
      newEntries.removeRange(0, newEntries.length - state.maxEntries);
    }

    state = state.copyWith(entries: newEntries);
  }

  void info(String message, {String? category, Map<String, dynamic>? metadata}) {
    addLog(LogLevel.info, message, category: category, metadata: metadata);
  }

  void warning(String message, {String? category, Map<String, dynamic>? metadata}) {
    addLog(LogLevel.warning, message, category: category, metadata: metadata);
  }

  void error(String message, {String? category, Map<String, dynamic>? metadata}) {
    addLog(LogLevel.error, message, category: category, metadata: metadata);
  }

  void debug(String message, {String? category, Map<String, dynamic>? metadata}) {
    addLog(LogLevel.debug, message, category: category, metadata: metadata);
  }

  void network(String message, {String? category, Map<String, dynamic>? metadata}) {
    addLog(LogLevel.network, message, category: category, metadata: metadata);
  }

  void logHttpRequest(String method, String url, {int? statusCode, String? error}) {
    final message = statusCode != null
        ? '$method $url → $statusCode'
        : error != null
        ? '$method $url → ERROR: $error'
        : '$method $url';

    final level = error != null
        ? LogLevel.error
        : (statusCode != null && statusCode >= 400)
        ? LogLevel.warning
        : LogLevel.network;

    addLog(level, message,
        category: 'HTTP',
        metadata: {
          'method': method,
          'url': url,
          if (statusCode != null) 'statusCode': statusCode,
          if (error != null) 'error': error,
        });
  }

  void logDownloadStart(String url, String fileName) {
    addLog(LogLevel.info, 'Starting download: $fileName',
        category: 'Download',
        metadata: {'url': url, 'fileName': fileName});
  }

  void logDownloadComplete(String fileName, {int? size}) {
    final sizeText = size != null ? ' (${(size / 1024 / 1024).toStringAsFixed(2)} MB)' : '';
    addLog(LogLevel.info, 'Download completed: $fileName$sizeText',
        category: 'Download',
        metadata: {'fileName': fileName, if (size != null) 'size': size});
  }

  void logDownloadError(String fileName, String error) {
    addLog(LogLevel.error, 'Download failed: $fileName - $error',
        category: 'Download',
        metadata: {'fileName': fileName, 'error': error});
  }

  void logProxyConfiguration(String? proxyUrl) {
    if (proxyUrl != null && proxyUrl.isNotEmpty) {
      addLog(LogLevel.info, 'Proxy configured: $proxyUrl', category: 'Network');
    } else {
      addLog(LogLevel.info, 'Proxy disabled', category: 'Network');
    }
  }

  void toggleVisibility() {
    state = state.copyWith(isVisible: !state.isVisible);
  }

  void setVisibleLevels(Set<LogLevel> levels) {
    state = state.copyWith(visibleLevels: levels);
  }

  void setFilter(String? filter) {
    state = state.copyWith(filterText: filter);
  }

  void clearLogs() {
    state = state.copyWith(entries: []);
  }

  void exportLogs() {
    info('Logs exported (${state.entries.length} entries)', category: 'System');
    // In a real implementation, you'd save this to a file or copy to clipboard
    // final logs = state.entries.map((e) => e.toString()).join('\n');
  }
}
