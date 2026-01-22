import 'package:hooks_riverpod/hooks_riverpod.dart' show StateNotifier;
import 'package:tts_mod_vault/src/models/log_entry.dart'
    show LogEntry, LogLevel;

class LogNotifier extends StateNotifier<List<LogEntry>> {
  static const int maxEntries = 10000;

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
