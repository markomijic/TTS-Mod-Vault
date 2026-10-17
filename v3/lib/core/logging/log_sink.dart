import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';

/// Destination for [LogEntry]s outside the in-memory store (a file, the
/// debugger console, a test collector).
abstract interface class LogSink {
  /// Accepts an entry. Must not throw and should return quickly; buffer and
  /// write later if the destination is slow.
  void write(LogEntry entry);

  /// Writes out anything buffered.
  Future<void> flush();

  /// Flushes and releases resources. Entries written afterwards are dropped.
  Future<void> close();
}

/// Appends `LogEntry.toLine()` lines to `<directory>/<baseName>.log` and
/// rotates by size.
///
/// When appending a line would push the current file past [maxBytes], the
/// files are shifted (`vault.log` -> `vault.1.log` -> `vault.2.log`, the
/// oldest beyond [maxFiles] is deleted) and a new `vault.log` is started.
/// Writes are buffered in memory and written by a short [flushInterval]
/// timer, or immediately on [flush] and [close].
///
/// The sink never throws into the caller: IO errors are swallowed and the
/// most recent one is kept in [lastError] / [lastErrorStackTrace] so the app
/// can surface it (for example in the log panel header).
final class RotatingFileLogSink implements LogSink {
  /// Creates a sink writing into [directory] (created on first flush).
  ///
  /// [fileSystem] defaults to the real disk; tests pass a `MemoryFileSystem`.
  RotatingFileLogSink({
    required this.directory,
    FileSystem? fileSystem,
    this.baseName = 'vault',
    this.maxBytes = defaultMaxBytes,
    this.maxFiles = defaultMaxFiles,
    this.flushInterval = const Duration(milliseconds: 500),
  }) : _fileSystem = fileSystem ?? const LocalFileSystem() {
    if (maxBytes < 1) {
      throw ArgumentError.value(maxBytes, 'maxBytes', 'must be positive');
    }
    if (maxFiles < 1) {
      throw ArgumentError.value(maxFiles, 'maxFiles', 'must be at least 1');
    }
  }

  /// Default rotation threshold: 5 MB.
  static const int defaultMaxBytes = 5 * 1024 * 1024;

  /// Default number of files kept (current plus two rotated).
  static const int defaultMaxFiles = 3;

  /// Directory containing the log files (created on first flush).
  final String directory;

  /// File name without extension (`vault` -> `vault.log`, `vault.1.log`).
  final String baseName;

  /// Size at which the current file is rotated.
  final int maxBytes;

  /// Total number of log files kept, including the current one.
  final int maxFiles;

  /// Delay between a buffered write and the timer-driven flush.
  final Duration flushInterval;

  final FileSystem _fileSystem;
  final List<String> _buffer = [];
  Timer? _timer;
  Future<void> _pendingFlush = Future<void>.value();
  int? _currentSize;
  bool _closed = false;
  Object? _lastError;
  StackTrace? _lastErrorStackTrace;

  /// Path of the current log file.
  String get filePath => _pathFor(0);

  Object? get lastError => _lastError;

  /// Stack trace of [lastError].
  StackTrace? get lastErrorStackTrace => _lastErrorStackTrace;

  /// Whether [close] has been called.
  bool get isClosed => _closed;

  /// Number of lines waiting to be written.
  int get bufferedLineCount => _buffer.length;

  /// Paths of all files this sink may write, current file first.
  List<String> get filePaths => List.generate(maxFiles, _pathFor);

  @override
  void write(LogEntry entry) {
    if (_closed) {
      return;
    }
    try {
      _buffer.add(entry.toLine());
      _timer ??= Timer(flushInterval, _onTimer);
    } catch (error, stackTrace) {
      _remember(error, stackTrace);
    }
  }

  @override
  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (_buffer.isEmpty) {
      return _pendingFlush;
    }
    final lines = List<String>.of(_buffer);
    _buffer.clear();
    // Serialise flushes so appends never interleave.
    return _pendingFlush = _pendingFlush.then((_) => _writeLines(lines));
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return _pendingFlush;
    }
    await flush();
    _closed = true;
  }

  void _onTimer() {
    _timer = null;
    flush().ignore();
  }

  Future<void> _writeLines(List<String> lines) async {
    try {
      final file = _fileSystem.file(filePath);
      await file.parent.create(recursive: true);
      var size = _currentSize ??= file.existsSync() ? await file.length() : 0;
      final chunk = BytesBuilder(copy: false);
      for (final line in lines) {
        final bytes = utf8.encode('$line\n');
        final written = size + chunk.length;
        if (written > 0 && written + bytes.length > maxBytes) {
          if (chunk.isNotEmpty) {
            await _append(file, chunk.takeBytes());
          }
          await _rotate();
          size = 0;
        }
        chunk.add(bytes);
      }
      if (chunk.isNotEmpty) {
        await _append(file, chunk.takeBytes());
      }
    } catch (error, stackTrace) {
      _remember(error, stackTrace);
    }
  }

  Future<void> _append(File file, Uint8List bytes) async {
    await file.writeAsBytes(bytes, mode: FileMode.append, flush: true);
    _currentSize = (_currentSize ?? 0) + bytes.length;
  }

  Future<void> _rotate() async {
    final oldest = _fileSystem.file(_pathFor(maxFiles - 1));
    if (oldest.existsSync()) {
      await oldest.delete();
    }
    for (var index = maxFiles - 2; index >= 0; index--) {
      final file = _fileSystem.file(_pathFor(index));
      if (file.existsSync()) {
        await file.rename(_pathFor(index + 1));
      }
    }
    _currentSize = 0;
  }

  String _pathFor(int index) {
    final name = index == 0 ? '$baseName.log' : '$baseName.$index.log';
    return _fileSystem.path.join(directory, name);
  }

  void _remember(Object error, StackTrace stackTrace) {
    _lastError = error;
    _lastErrorStackTrace = stackTrace;
  }
}
