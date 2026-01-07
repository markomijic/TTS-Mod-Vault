import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/src/models/log_entry.dart';

class LogNotifier extends StateNotifier<List<LogEntry>> {
  static const int maxEntries = 1000;

  LogNotifier() : super([]);

  /// Add an info-level log entry
  void addInfo(String message) {
    _addEntry(LogEntry(message: message, level: LogLevel.info));
  }

  /// Add a success-level log entry
  void addSuccess(String message) {
    _addEntry(LogEntry(message: message, level: LogLevel.success));
  }

  /// Add a warning-level log entry
  void addWarning(String message) {
    _addEntry(LogEntry(message: message, level: LogLevel.warning));
  }

  /// Add an error-level log entry
  void addError(String message) {
    _addEntry(LogEntry(message: message, level: LogLevel.error));
  }

  /// Add a log entry to the list, maintaining max entry limit
  void _addEntry(LogEntry entry) {
    final newState = [...state, entry];

    // Remove oldest entries if we exceed the limit
    if (newState.length > maxEntries) {
      state = newState.sublist(newState.length - maxEntries);
    } else {
      state = newState;
    }
  }

  /// Clear all log entries
  void clear() {
    state = [];
  }
}

/// Provider for the log entries
final logProvider = StateNotifierProvider<LogNotifier, List<LogEntry>>((ref) {
  return LogNotifier();
});

/// Provider for filtered log entries based on search query
final filteredLogProvider = Provider.family<List<LogEntry>, String>((ref, searchQuery) {
  final logs = ref.watch(logProvider);

  if (searchQuery.isEmpty) {
    return logs;
  }

  final lowerQuery = searchQuery.toLowerCase();
  return logs.where((entry) {
    return entry.message.toLowerCase().contains(lowerQuery) ||
           entry.formattedTimestamp.contains(lowerQuery);
  }).toList();
});
