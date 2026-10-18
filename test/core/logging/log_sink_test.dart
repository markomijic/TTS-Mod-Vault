import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/logging/app_log.dart';

LogEntry entry(int id, String message, {LogLevel level = LogLevel.info}) =>
    LogEntry(
      id: id,
      time: DateTime(2026, 10, 17, 12),
      level: level,
      source: LogSource.app,
      message: message,
    );

/// Sink that records what it receives and optionally throws on write.
final class _RecordingSink implements LogSink {
  final List<LogEntry> written = [];
  int flushes = 0;
  bool closed = false;
  bool throwOnWrite = false;

  @override
  void write(LogEntry entry) {
    if (throwOnWrite) {
      throw StateError('sink broken');
    }
    written.add(entry);
  }

  @override
  Future<void> flush() async => flushes++;

  @override
  Future<void> close() async => closed = true;
}

void main() {
  group('RotatingFileLogSink', () {
    late FileSystem fs;
    const dir = '/data/logs';

    setUp(() {
      fs = MemoryFileSystem.test();
    });

    List<String> linesOf(String path) =>
        fs.file(path).readAsLinesSync().where((l) => l.isNotEmpty).toList();

    test('exposes paths for current and rotated files', () {
      final sink = RotatingFileLogSink(directory: dir, fileSystem: fs);
      expect(sink.filePath, '/data/logs/vault.log');
      expect(sink.filePaths, [
        '/data/logs/vault.log',
        '/data/logs/vault.1.log',
        '/data/logs/vault.2.log',
      ]);
    });

    test('validates constructor arguments', () {
      expect(
        () => RotatingFileLogSink(directory: dir, fileSystem: fs, maxBytes: 0),
        throwsArgumentError,
      );
      expect(
        () => RotatingFileLogSink(directory: dir, fileSystem: fs, maxFiles: 0),
        throwsArgumentError,
      );
    });

    test(
      'buffers writes and creates the directory and file on flush',
      () async {
        final sink = RotatingFileLogSink(directory: dir, fileSystem: fs);
        sink.write(entry(1, 'hello'));
        sink.write(entry(2, 'world'));
        expect(sink.bufferedLineCount, 2);
        expect(fs.file(sink.filePath).existsSync(), isFalse);

        await sink.flush();
        expect(sink.bufferedLineCount, 0);
        final lines = linesOf(sink.filePath);
        expect(lines, hasLength(2));
        expect(lines[0], endsWith('[INFO] [app] hello'));
        expect(lines[1], endsWith('[INFO] [app] world'));
        expect(sink.lastError, isNull);
        await sink.close();
      },
    );

    test('appends to an existing file across flushes', () async {
      final sink = RotatingFileLogSink(directory: dir, fileSystem: fs);
      sink.write(entry(1, 'one'));
      await sink.flush();
      sink.write(entry(2, 'two'));
      await sink.flush();
      expect(linesOf(sink.filePath), hasLength(2));
      await sink.close();
    });

    test('appends to a file left by a previous session', () async {
      fs.file('$dir/vault.log')
        ..createSync(recursive: true)
        ..writeAsStringSync('previous\n');
      final sink = RotatingFileLogSink(directory: dir, fileSystem: fs);
      sink.write(entry(1, 'new'));
      await sink.flush();
      expect(linesOf(sink.filePath).first, 'previous');
      expect(linesOf(sink.filePath).last, endsWith('new'));
      await sink.close();
    });

    test('flushes on the timer without an explicit flush', () async {
      final sink = RotatingFileLogSink(
        directory: dir,
        fileSystem: fs,
        flushInterval: const Duration(milliseconds: 20),
      );
      sink.write(entry(1, 'timed'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(linesOf(sink.filePath), hasLength(1));
      await sink.close();
    });

    test(
      'rotates when the file would exceed maxBytes, keeping maxFiles',
      () async {
        final lineLength = '${entry(1, 'm000').toLine()}\n'.length;
        // Room for exactly 3 lines per file.
        final sink = RotatingFileLogSink(
          directory: dir,
          fileSystem: fs,
          maxBytes: lineLength * 3,
        );
        for (var i = 0; i < 10; i++) {
          sink.write(entry(i, 'm${i.toString().padLeft(3, '0')}'));
          if (i.isEven) {
            await sink.flush();
          }
        }
        await sink.flush();

        final files =
            fs
                .directory(dir)
                .listSync()
                .map((e) => fs.path.basename(e.path))
                .toList()
              ..sort();
        expect(files, ['vault.1.log', 'vault.2.log', 'vault.log']);
        for (final name in files) {
          expect(
            fs.file('$dir/$name').lengthSync(),
            lessThanOrEqualTo(lineLength * 3),
          );
        }
        // Newest lines are in the current file, older ones shifted down.
        expect(linesOf('$dir/vault.log').last, endsWith('m009'));
        expect(linesOf('$dir/vault.1.log').first, endsWith('m006'));
        expect(linesOf('$dir/vault.2.log').first, endsWith('m003'));
        // m000..m002 fell off the end.
        expect(sink.lastError, isNull);
        await sink.close();
      },
    );

    test('rotation within a single flush splits the buffered lines', () async {
      final lineLength = '${entry(1, 'm000').toLine()}\n'.length;
      final sink = RotatingFileLogSink(
        directory: dir,
        fileSystem: fs,
        maxBytes: lineLength * 2,
        maxFiles: 2,
      );
      for (var i = 0; i < 5; i++) {
        sink.write(entry(i, 'm${i.toString().padLeft(3, '0')}'));
      }
      await sink.flush();
      expect(linesOf('$dir/vault.log').map((l) => l.substring(l.length - 4)), [
        'm004',
      ]);
      expect(
        linesOf('$dir/vault.1.log').map((l) => l.substring(l.length - 4)),
        ['m002', 'm003'],
      );
      expect(fs.file('$dir/vault.2.log').existsSync(), isFalse);
      await sink.close();
    });

    test('with maxFiles 1 the current file is simply truncated', () async {
      final lineLength = '${entry(1, 'm000').toLine()}\n'.length;
      final sink = RotatingFileLogSink(
        directory: dir,
        fileSystem: fs,
        maxBytes: lineLength * 2,
        maxFiles: 1,
      );
      for (var i = 0; i < 3; i++) {
        sink.write(entry(i, 'm00$i'));
      }
      await sink.flush();
      expect(linesOf('$dir/vault.log'), hasLength(1));
      expect(fs.directory(dir).listSync(), hasLength(1));
      await sink.close();
    });

    test('a line larger than maxBytes is still written', () async {
      final sink = RotatingFileLogSink(
        directory: dir,
        fileSystem: fs,
        maxBytes: 10,
      );
      sink.write(entry(1, 'a long message'));
      sink.write(entry(2, 'another long message'));
      await sink.flush();
      expect(linesOf('$dir/vault.log'), hasLength(1));
      expect(linesOf('$dir/vault.1.log'), hasLength(1));
      await sink.close();
    });

    test('close flushes and drops later writes', () async {
      final sink = RotatingFileLogSink(directory: dir, fileSystem: fs);
      sink.write(entry(1, 'before'));
      await sink.close();
      expect(sink.isClosed, isTrue);
      sink.write(entry(2, 'after'));
      await sink.flush();
      await sink.close();
      expect(linesOf(sink.filePath), hasLength(1));
    });

    test('swallows IO errors and remembers the last one', () async {
      // A file where the directory should be makes directory creation fail.
      fs.file('/blocked').createSync();
      final sink = RotatingFileLogSink(
        directory: '/blocked/logs',
        fileSystem: fs,
      );
      sink.write(entry(1, 'x'));
      await expectLater(sink.flush(), completes);
      expect(sink.lastError, isNotNull);
      expect(sink.lastErrorStackTrace, isNotNull);
      await sink.close();
    });
  });

  group('AppLog', () {
    test('forwards every store entry to every sink synchronously', () async {
      final store = LogStore();
      final a = _RecordingSink();
      final b = _RecordingSink();
      final log = AppLog(store: store, sinks: [a, b]);

      log.info(LogSource.app, 'via facade');
      store.warning(LogSource.library, 'direct to store');
      expect(a.written.map((e) => e.message), [
        'via facade',
        'direct to store',
      ]);
      expect(b.written.map((e) => e.message), [
        'via facade',
        'direct to store',
      ]);
      expect(store.unseenWarningsAndErrors, 1);
      await log.dispose();
    });

    test('a throwing sink does not affect the caller or other sinks', () async {
      final broken = _RecordingSink()..throwOnWrite = true;
      final healthy = _RecordingSink();
      final log = AppLog(store: LogStore(), sinks: [broken, healthy]);
      expect(() => log.error(LogSource.download, 'boom'), returnsNormally);
      expect(healthy.written, hasLength(1));
      await log.dispose();
    });

    test('error renders error and stack trace into details', () async {
      final log = AppLog(store: LogStore());
      final entry = log.error(
        LogSource.download,
        'Download failed',
        details: 'Mod: X',
        error: const FormatException('bad bytes'),
        stackTrace: StackTrace.fromString('#0 main (file.dart:1:1)'),
      );
      expect(entry.details, startsWith('Mod: X\n'));
      expect(entry.details, contains('FormatException: bad bytes'));
      expect(entry.details, endsWith('#0 main (file.dart:1:1)'));
      expect(
        log.error(LogSource.app, 'plain', details: 'only').details,
        'only',
      );
      await log.dispose();
    });

    test('flush and dispose reach the sinks and stop forwarding', () async {
      final store = LogStore();
      final sink = _RecordingSink();
      final log = AppLog(store: store, sinks: [sink]);
      await log.flush();
      expect(sink.flushes, 1);

      await log.dispose();
      expect(log.isDisposed, isTrue);
      expect(sink.closed, isTrue);
      store.info(LogSource.app, 'after dispose');
      expect(sink.written, isEmpty);
      await log.dispose();
    });

    test('shortcuts set the matching level', () async {
      final log = AppLog(store: LogStore());
      expect(log.info(LogSource.app, 'x').level, LogLevel.info);
      expect(log.success(LogSource.app, 'x').level, LogLevel.success);
      expect(log.warning(LogSource.app, 'x').level, LogLevel.warning);
      expect(log.error(LogSource.app, 'x').level, LogLevel.error);
      expect(log.debugLog(LogSource.app, 'x').level, LogLevel.debug);
      expect(
        log.log(LogLevel.success, LogSource.backup, 'x', url: 'u').url,
        'u',
      );
      await log.dispose();
    });

    test('works end to end with a rotating file sink', () async {
      final fs = MemoryFileSystem.test();
      final fileSink = RotatingFileLogSink(directory: '/logs', fileSystem: fs);
      final log = AppLog(store: LogStore(), sinks: [fileSink]);
      log.info(LogSource.library, 'Refreshed 1234 mods');
      log.error(LogSource.download, 'Download failed', url: 'https://x/y');
      await log.dispose();
      final lines = fs.file('/logs/vault.log').readAsLinesSync();
      expect(lines, hasLength(2));
      expect(
        lines[1],
        contains('[ERROR] [download] Download failed | url=https://x/y'),
      );
    });
  });
}
