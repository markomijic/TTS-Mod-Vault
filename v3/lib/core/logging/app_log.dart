import 'dart:async';

import 'package:tts_mod_vault/core/logging/log_entry.dart';
import 'package:tts_mod_vault/core/logging/log_sink.dart';
import 'package:tts_mod_vault/core/logging/log_store.dart';

export 'package:tts_mod_vault/core/logging/log_entry.dart';
export 'package:tts_mod_vault/core/logging/log_sink.dart';
export 'package:tts_mod_vault/core/logging/log_store.dart';

/// Application logging facade: one [LogStore] (what the log panel shows)
/// wired to any number of [LogSink]s (the rotating file, a test collector).
///
/// There is deliberately no global instance. Create one at bootstrap and
/// provide it through Riverpod, so features depend on an injected `AppLog`
/// and tests can substitute a store without sinks:
///
/// ```dart
/// final appLogProvider = Provider<AppLog>((ref) {
///   final log = AppLog(
///     store: LogStore(),
///     sinks: [RotatingFileLogSink(directory: logDir)],
///   );
///   ref.onDispose(log.dispose);
///   return log;
/// });
/// ```
///
/// Every entry appended to [store], whether through this facade or directly,
/// is forwarded synchronously to each sink; a sink that throws is isolated
/// from the others and from the caller.
final class AppLog {
  /// Creates the facade and starts forwarding [store] entries to [sinks].
  AppLog({required this.store, List<LogSink> sinks = const []})
    : _sinks = List<LogSink>.unmodifiable(sinks) {
    _subscription = store.onEntry.listen(_forward);
  }

  /// The in-memory store behind the log panel.
  final LogStore store;

  final List<LogSink> _sinks;
  late final StreamSubscription<LogEntry> _subscription;
  bool _disposed = false;

  /// Sinks receiving every entry.
  List<LogSink> get sinks => _sinks;

  /// Whether [dispose] has been called.
  bool get isDisposed => _disposed;

  /// Appends an entry (see [LogStore.log]).
  LogEntry log(
    LogLevel level,
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => store.log(
    level,
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends an [LogLevel.info] entry.
  LogEntry info(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => store.info(
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
  }) => store.success(
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
  }) => store.warning(
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends an [LogLevel.error] entry. Pass the caught error and trace as
  /// [error] / [stackTrace] to have them rendered into `details`.
  LogEntry error(
    LogSource source,
    String message, {
    Object? error,
    StackTrace? stackTrace,
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => store.error(
    source,
    message,
    details: _detailsFrom(details, error, stackTrace),
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Appends a [LogLevel.debug] entry.
  LogEntry debugLog(
    LogSource source,
    String message, {
    String? details,
    String? modPath,
    String? url,
    String? operationId,
  }) => store.debugLog(
    source,
    message,
    details: details,
    modPath: modPath,
    url: url,
    operationId: operationId,
  );

  /// Flushes every sink.
  Future<void> flush() =>
      Future.wait(_sinks.map((sink) => sink.flush())).then((_) {});

  /// Stops forwarding, closes every sink and disposes the store.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    await _subscription.cancel();
    await Future.wait(_sinks.map((sink) => sink.close()));
    await store.dispose();
  }

  void _forward(LogEntry entry) {
    for (final sink in _sinks) {
      try {
        sink.write(entry);
      } catch (_) {
        // A misbehaving sink must never break logging for the others.
      }
    }
  }

  static String? _detailsFrom(
    String? details,
    Object? error,
    StackTrace? stackTrace,
  ) {
    if (error == null && stackTrace == null) {
      return details;
    }
    final buffer = StringBuffer();
    if (details != null && details.isNotEmpty) {
      buffer.writeln(details);
    }
    if (error != null) {
      buffer.writeln(error);
    }
    if (stackTrace != null) {
      buffer.write(stackTrace);
    }
    return buffer.toString().trimRight();
  }
}
