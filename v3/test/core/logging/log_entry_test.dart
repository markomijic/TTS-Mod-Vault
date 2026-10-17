import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/core/logging/log_entry.dart';

void main() {
  final time = DateTime(2026, 10, 17, 14, 3, 11, 123);

  group('LogEntry.toLine', () {
    test('renders the full format with every part', () {
      final entry = LogEntry(
        id: 1,
        time: time,
        level: LogLevel.error,
        source: LogSource.download,
        message: 'Download failed (404 Not Found)',
        details: 'Mod: X, type: Images',
        modPath: r'D:\Mods\Workshop\123.json',
        url: 'https://example.com/a.png',
        operationId: 'op-7',
      );
      expect(
        entry.toLine(),
        '[2026-10-17 14:03:11.123] [ERROR] [download] '
        'Download failed (404 Not Found) | Mod: X, type: Images | '
        r'mod=D:\Mods\Workshop\123.json | url=https://example.com/a.png | '
        'op=op-7',
      );
    });

    test('omits empty and null parts', () {
      final entry = LogEntry(
        id: 2,
        time: time,
        level: LogLevel.info,
        source: LogSource.library,
        message: 'Refreshing library',
        details: '',
        url: '',
      );
      expect(
        entry.toLine(),
        '[2026-10-17 14:03:11.123] [INFO] [library] Refreshing library',
      );
    });

    test('escapes line breaks so an entry stays on one line', () {
      final entry = LogEntry(
        id: 3,
        time: time,
        level: LogLevel.warning,
        source: LogSource.import,
        message: 'first\nsecond',
        details: 'a\r\nb\rc\nd',
      );
      final line = entry.toLine();
      expect(line.contains('\n'), isFalse);
      expect(line.contains('\r'), isFalse);
      expect(line, contains(r'first\nsecond'));
      expect(line, contains(r'a\nb\nc\nd'));
    });

    test('uses camelCase source names and upper-case level labels', () {
      final entry = LogEntry(
        id: 4,
        time: time,
        level: LogLevel.success,
        source: LogSource.urlCheck,
        message: 'ok',
      );
      expect(entry.toLine(), contains('[SUCCESS] [urlCheck] ok'));
    });

    test('formatTimestamp pads every component', () {
      expect(
        LogEntry.formatTimestamp(DateTime(2026, 1, 2, 3, 4, 5, 6)),
        '2026-01-02 03:04:05.006',
      );
    });
  });

  test('LogLevel.isWarningOrError covers only warning and error', () {
    expect(LogLevel.values.where((l) => l.isWarningOrError), [
      LogLevel.warning,
      LogLevel.error,
    ]);
  });
}
