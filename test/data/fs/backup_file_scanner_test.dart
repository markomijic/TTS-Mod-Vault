import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tts_mod_vault/data/fs/backup_file_scanner.dart';

File writeFile(FileSystem fs, String path, [String content = 'PK']) =>
    fs.file(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);

void main() {
  group('scanBackupFilesWith (posix memory fs)', () {
    late MemoryFileSystem fs;
    const backups = '/backups';

    setUp(() {
      fs = MemoryFileSystem.test();
      fs.directory(backups).createSync(recursive: true);
    });

    Future<BackupScanResult> scan([String dir = backups]) =>
        scanBackupFilesWith(BackupScanRequest(backupsDir: dir), fs);

    test('lists .ttsmod files recursively with stats', () async {
      final a = writeFile(fs, '$backups/Mod A (123).ttsmod', '0123456789');
      writeFile(fs, '$backups/Old/Mod B (456).TTSMOD', 'abc');
      writeFile(fs, '$backups/notes.txt');
      writeFile(fs, '$backups/archive.zip');
      writeFile(fs, '$backups/ttsmod'); // no extension
      a.setLastModifiedSync(DateTime.utc(2025, 6, 7, 8, 9, 10));

      final result = await scan();

      expect(result.warnings, isEmpty);
      expect(
        result.entries.map((e) => e.path),
        unorderedEquals([
          '/backups/Mod A (123).ttsmod',
          '/backups/Old/Mod B (456).TTSMOD',
        ]),
      );
      final first = result.entries.singleWhere((e) => e.folder == 'backups');
      expect(first.fileName, 'Mod A (123).ttsmod');
      expect(first.sizeBytes, 10);
      expect(
        first.mtimeMs,
        DateTime.utc(2025, 6, 7, 8, 9, 10).millisecondsSinceEpoch,
      );
      final second = result.entries.singleWhere((e) => e.folder == 'Old');
      expect(second.fileName, 'Mod B (456).TTSMOD');
      expect(second.sizeBytes, 3);
    });

    test('empty directory string returns a warning', () async {
      final result = await scan('   ');
      expect(result.entries, isEmpty);
      expect(result.warnings.single, contains('not set'));
    });

    test('missing directory returns empty entries and a warning', () async {
      final result = await scan('/nope');
      expect(result.entries, isEmpty);
      expect(result.warnings.single, contains('Directory not found'));
    });

    test('empty directory returns no entries and no warnings', () async {
      final result = await scan();
      expect(result.entries, isEmpty);
      expect(result.warnings, isEmpty);
    });

    test('normalises paths', () async {
      writeFile(fs, '$backups/a.ttsmod');
      final result = await scan('/backups/./');
      expect(result.entries.single.path, '/backups/a.ttsmod');
    });
  });

  group('scanBackupFilesWith (windows memory fs)', () {
    test('returns backslash paths and folder names', () async {
      final fs = MemoryFileSystem.test(style: FileSystemStyle.windows);
      final backups = fs.path.join(r'C:\', 'Backups');
      writeFile(fs, fs.path.join(backups, 'Sub Folder', 'Mod (1).ttsmod'));

      final result = await scanBackupFilesWith(
        const BackupScanRequest(backupsDir: 'C:/Backups'),
        fs,
      );

      expect(result.warnings, isEmpty);
      final entry = result.entries.single;
      expect(entry.path, r'C:\Backups\Sub Folder\Mod (1).ttsmod');
      expect(entry.fileName, 'Mod (1).ttsmod');
      expect(entry.folder, 'Sub Folder');
    });
  });
}
