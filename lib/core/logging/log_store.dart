import 'dart:async';
import 'dart:collection';

import 'package:tts_mod_vault/core/logging/log_entry.dart';

/// In-memory, bounded store of [LogEntry]s that backs the log panel.
///
/// Appends are synchronous: `log()` returns the created entry and listeners
/// of [onEntry] are notified before it returns, so a file sink attached to
/// the stream sees entries in order even when the app is about to exit.
/// The store keeps the newest [capacity] entries (oldest are evicted first);
/// ids keep increasing across evictions and [clear] calls, so an id uniquely
/// identifies an entry for the lifetime of the store.
///
/// This class has no Flutter dependency and is safe to use in tests.
final class LogStore {
  /// Creates a store keeping at most [capacity] entries.
  LogStore({this.capacity = defaultCapacity}) {
    if (capacity < 1) {
      throw ArgumentError.value(capacity, 'capacity', 'must be at least 1');
    }
  }

  /// Default number of entries kept in memory (v2 used the same bound).
  static const int defaultCapacity = 10000;

  /// Maximum number of entries kept in memory.
  final int capacity;

  final ListQueue<LogEntry> _entries = ListQueue<LogEntry>();
  final StreamController<LogEntry> _controller =
      StreamController<LogEntry>.broadcast(sync: true);
  int _nextId = 1;
  int _unseenWarningsAndErrors = 0;

  /// Snapshot of the stored entries, oldest first.
  List<LogEntry> get entries => List<LogEntry>.unmodifiable(_entries);

  /// Number of stored entries.
  int get length => _entries.length;

  /// The newest entry, or `null` when the store is empty.
  LogEntry? get last => _entries.isEmpty ? null : _entries.last;

  /// Emits every appended entry, synchronously from within `log()`.
  Stream<LogEntry> get onEntry => _controller.stream;

  /// Number of warning and error entries appended since the last [markSeen].
  int get unseenWarningsAndErrors => _unseenWarningsAndErrors;

  /// Resets [unseenWarningsAndErrors] to zero (the user expanded the panel).
  void markSeen() => _unseenWarningsAndErrors = 0;

  /// Removes all entries and resets the unseen counter. Ids are not reset.
  void clear() {
    _entries.clear();
    _unseenWarningsAndErrors = 0;
  }

  /// Appends an entry and returns it.
  LogEntry log(
    LogLevel level,
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
    DateTime? time,
  }) {
    final entry = LogEntry(
      id: _nextId++,
      time: time ?? DateTime.now(),
      level: level,
      source: source,
      message: message,
      details: details,
      modPath: modPath,
      url: url,
      operationId: operationId,
    );
    if (_entries.length >= capacity) {
      _entries.removeFirst();
    }
    _entries.addLast(entry);
    if (level.isWarningOrError) {
      _unseenWarningsAndErrors++;
    }
    if (!_controller.isClosed) {
      _controller.add(entry);
    }
    return entry;
  }

  /// Appends an [LogLevel.info] entry.
  LogEntry info(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => log(
    LogLevel.info,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends a [LogLevel.success] entry.
  LogEntry success(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => log(
    LogLevel.success,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends a [LogLevel.warning] entry.
  LogEntry warning(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => log(
    LogLevel.warning,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends an [LogLevel.error] entry.
  LogEntry error(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => log(
    LogLevel.error,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends a [LogLevel.debug] entry. Named `debugLog` so it does not clash
  /// with the conventional `debug` identifier in callers.
  LogEntry debugLog(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => log(
    LogLevel.debug,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Closes [onEntry]. Further `log()` calls still append to the ring but
  /// are no longer broadcast.
  Future<void> dispose() => _controller.close();
}
