import 'dart:io' show Platform;

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:file/memory.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:tts_mod_vault/data/fs/file_ops.dart';

void main() {
  late FileSystem fs;
  late String dir;

  setUp(() {
    // Match the host's path style so `package:path` (which follows the host)
    // and the in-memory file system agree on separators.
    fs = MemoryFileSystem(
      style: Platform.isWindows
          ? FileSystemStyle.windows
          : FileSystemStyle.posix,
    );
    dir = fs.path.join(fs.currentDirectory.path, 'cache');
    fs.directory(dir).createSync(recursive: true);
  });

  group('writeStringPreservingCreationTime', () {
    test('replaces the contents of an existing file', () async {
      final path = fs.path.join(dir, 'mod.json');
      fs.file(path).writeAsStringSync('{"SaveName":"a long old value"}');

      await fs.writeStringPreservingCreationTime(path, '{"x":1}');

      expect(fs.file(path).readAsStringSync(), '{"x":1}');
    });

    test('creates the file when it does not exist', () async {
      final path = fs.path.join(dir, 'new.json');

      await fs.writeStringPreservingCreationTime(path, 'hello');

      expect(fs.file(path).readAsStringSync(), 'hello');
    });

    test('writes UTF-8', () async {
      final path = fs.path.join(dir, 'utf.json');

      await fs.writeStringPreservingCreationTime(path, 'Grüße 日本');

      expect(fs.file(path).readAsStringSync(), 'Grüße 日本');
    });
  });

  group('deleteIfExists', () {
    test('deletes an existing file and reports it', () async {
      final path = fs.path.join(dir, 'a.png');
      fs.file(path).writeAsBytesSync(const [1]);

      expect(await fs.deleteIfExists(path), isTrue);
      expect(fs.file(path).existsSync(), isFalse);
    });

    test('is a no-op for a missing file', () async {
      expect(await fs.deleteIfExists(fs.path.join(dir, 'nope.png')), isFalse);
    });
  });

  group('renameKeepingExtension', () {
    test('renames within the folder and keeps the extension', () async {
      final path = fs.path.join(dir, 'old.jpg');
      fs.file(path).writeAsBytesSync(const [1, 2]);

      final newPath = await fs.renameKeepingExtension(path, 'new');

      expect(newPath, fs.path.join(dir, 'new.jpg'));
      expect(fs.file(path).existsSync(), isFalse);
      expect(fs.file(newPath!).readAsBytesSync(), [1, 2]);
    });

    test('returns null when the source is gone', () async {
      expect(
        await fs.renameKeepingExtension(fs.path.join(dir, 'gone.png'), 'x'),
        isNull,
      );
    });

    test('returns the same path when the name does not change', () async {
      final path = fs.path.join(dir, 'same.png');
      fs.file(path).writeAsBytesSync(const [1]);

      expect(await fs.renameKeepingExtension(path, 'same'), path);
      expect(fs.file(path).existsSync(), isTrue);
    });

    test('refuses to overwrite an existing target', () async {
      final path = fs.path.join(dir, 'a.png');
      final taken = fs.path.join(dir, 'b.png');
      fs.file(path).writeAsBytesSync(const [1]);
      fs.file(taken).writeAsBytesSync(const [2]);

      await expectLater(
        fs.renameKeepingExtension(path, 'b'),
        throwsA(isA<FileSystemException>()),
      );
      expect(fs.file(path).readAsBytesSync(), [1]);
      expect(fs.file(taken).readAsBytesSync(), [2]);
    });
  });

  test('fileSystemProvider defaults to the local file system', () {
    final container = ProviderContainer.test();
    expect(container.read(fileSystemProvider), isA<LocalFileSystem>());
  });
}
