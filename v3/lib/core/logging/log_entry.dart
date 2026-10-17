/// Severity of a [LogEntry].
enum LogLevel {
  /// Neutral progress information ("Refreshing library").
  info,

  /// A completed operation ("Downloaded 42/45 files").
  success,

  /// Something was skipped or degraded but the operation went on.
  warning,

  /// An operation or a step of it failed.
  error,

  /// Developer detail (provider observer events, timings); hidden by default.
  debug;

  /// Upper-case label used in [LogEntry.toLine] (`ERROR`, `INFO`, ...).
  String get label => name.toUpperCase();

  /// Whether this level counts towards the unseen warnings and errors badge.
  bool get isWarningOrError => this == warning || this == error;
}

/// Subsystem that produced a [LogEntry]; used for filtering in the log panel.
enum LogSource {
  /// Startup, window, settings migration, uncaught errors.
  app,

  /// Library index refresh: scanning mods, saves, saved objects.
  library,

  /// Asset downloads.
  download,

  /// Bulk and single URL availability checks.
  urlCheck,

  /// Steam Workshop download and update.
  workshop,

  /// Backup creation and backup index.
  backup,

  /// `.ttsmod` and JSON imports.
  import,

  /// Orphaned asset scan and asset deletion.
  cleanup,

  /// Settings reads and writes.
  settings,

  /// Debug-only instrumentation (Riverpod observer, debugPrint capture).
  debug,
}

/// One immutable line in the application log.
///
/// Entries are created by `LogStore.log` which assigns the monotonic [id];
/// code elsewhere should not construct them directly except in tests.
final class LogEntry {
  /// Creates an entry. Prefer `LogStore.log` and its shortcuts.
  const LogEntry({
    required this.id,
    required this.time,
    required this.level,
    required this.source,
    required this.message,
    this.details,
    this.modPath,
    this.url,
    this.operationId,
  });

  /// Monotonically increasing identifier assigned by the store.
  final int id;

  /// When the entry was created (local time).
  final DateTime time;

  /// Severity.
  final LogLevel level;

  /// Producing subsystem.
  final LogSource source;

  /// Short one-line description.
  final String message;

  /// Optional longer detail (an error's `toString()`, a response body, ...).
  final String? details;

  /// Path of the mod JSON this entry relates to, if any; lets the log panel
  /// select the mod on click.
  final String? modPath;

  /// URL this entry relates to, if any.
  final String? url;

  /// Identifier of the operation run this entry belongs to, if any.
  final String? operationId;

  /// Renders the entry as a single text line for the log file, for example:
  ///
  /// `[2026-10-17 14:03:11.123] [ERROR] [download] message | details | mod=... | url=...`
  ///
  /// Empty parts are omitted and line breaks in [message] and [details] are
  /// escaped as `\n` so one entry always occupies one line.
  String toLine() {
    final buffer = StringBuffer()
      ..write('[')
      ..write(formatTimestamp(time))
      ..write('] [')
      ..write(level.label)
      ..write('] [')
      ..write(source.name)
      ..write('] ')
      ..write(_escape(message));
    final details = this.details;
    if (details != null && details.isNotEmpty) {
      buffer
        ..write(' | ')
        ..write(_escape(details));
    }
    final modPath = this.modPath;
    if (modPath != null && modPath.isNotEmpty) {
      buffer
        ..write(' | mod=')
        ..write(_escape(modPath));
    }
    final url = this.url;
    if (url != null && url.isNotEmpty) {
      buffer
        ..write(' | url=')
        ..write(_escape(url));
    }
    final operationId = this.operationId;
    if (operationId != null && operationId.isNotEmpty) {
      buffer
        ..write(' | op=')
        ..write(_escape(operationId));
    }
    return buffer.toString();
  }

  /// Formats [time] as `yyyy-MM-dd HH:mm:ss.SSS` without an `intl` dependency.
  static String formatTimestamp(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    final year = time.year.toString().padLeft(4, '0');
    final millis = time.millisecond.toString().padLeft(3, '0');
    return '$year-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}:${two(time.second)}.$millis';
  }

  static String _escape(String text) {
    if (!text.contains('\n') && !text.contains('\r')) {
      return text;
    }
    return text
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\n');
  }

  @override
  String toString() => 'LogEntry(#$id ${toLine()})';
}
