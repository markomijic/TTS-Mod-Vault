// The streaming zip writer against a temp directory (archive streams need
// dart:io paths).

import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart' show ZipDecoder;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tts_mod_vault/core/cancellation/cancellation_token.dart';
import 'package:tts_mod_vault/data/fs/zip/zip_writer.dart';

void main() {
  late Directory temp;

  setUp(() => temp = Directory.systemTemp.createTempSync('ttsmv_zipw_'));
  tearDown(() => temp.deleteSync(recursive: true));

  String write(String name, List<int> bytes) {
    final file = File(p.join(temp.path, name))
      ..createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    return file.path;
  }

  Map<String, Uint8List> readBack(String zipPath) {
    final archive = ZipDecoder().decodeBytes(File(zipPath).readAsBytesSync());
    return {
      for (final file in archive)
        if (file.isFile) file.name: file.readBytes()!,
    };
  }

  group('writeZipArchive', () {
    test(
      'streams entries, normalises names and renames .part to the target',
      () async {
        final big = Uint8List(6 * 1024 * 1024);
        for (var i = 0; i < big.length; i++) {
          big[i] = (i * 31 + (i >> 10)) & 0xff;
        }
        final json = write('src/Mods/Workshop/1.json', '{"a":1}'.codeUnits);
        final asset = write('src/Mods/Images/asset.png', big);
        final target = p.join(temp.path, 'out', 'Mod (1).ttsmod');

        final result = await writeZipArchive(
          ZipWriteRequest(
            targetPath: target,
            entries: [
              (sourcePath: json, entryName: r'Mods\Workshop\1.json'),
              (sourcePath: asset, entryName: 'Mods/Images/asset.png'),
            ],
          ),
        );

        expect(result.written, 2);
        expect(result.skipped, isEmpty);
        expect(result.bytes, File(target).lengthSync());
        expect(File('$target$zipPartSuffix').existsSync(), isFalse);
        final entries = readBack(target);
        expect(entries.keys, ['Mods/Workshop/1.json', 'Mods/Images/asset.png']);
        expect(entries['Mods/Workshop/1.json'], '{"a":1}'.codeUnits);
        expect(entries['Mods/Images/asset.png'], big);
      },
    );

    test('skips missing sources and replaces an existing target', () async {
      final json = write('src/1.json', [1, 2, 3]);
      final target = p.join(temp.path, 'old.ttsmod');
      File(target).writeAsBytesSync([9, 9, 9]);

      final result = await writeZipArchive(
        ZipWriteRequest(
          targetPath: target,
          entries: [
            (sourcePath: json, entryName: 'Mods/Workshop/1.json'),
            (
              sourcePath: p.join(temp.path, 'src', 'gone.png'),
              entryName: 'Mods/Images/gone.png',
            ),
          ],
        ),
      );

      expect(result.written, 1);
      expect(result.skipped, [p.join(temp.path, 'src', 'gone.png')]);
      expect(readBack(target).keys, ['Mods/Workshop/1.json']);
    });

    test('a cancelled run leaves neither the archive nor a .part', () async {
      final a = write('src/a.bin', List.filled(1000, 1));
      final b = write('src/b.bin', List.filled(1000, 2));
      final target = p.join(temp.path, 'cancelled.ttsmod');
      var done = 0;

      await expectLater(
        writeZipArchiveWith(
          ZipWriteRequest(
            targetPath: target,
            entries: [
              (sourcePath: a, entryName: 'a.bin'),
              (sourcePath: b, entryName: 'b.bin'),
            ],
          ),
          onProgress: (progress) => done = progress.done,
          isCancelled: () => done >= 1,
        ),
        throwsA(isA<OperationCancelledException>()),
      );

      expect(done, 1);
      expect(File(target).existsSync(), isFalse);
      expect(File('$target$zipPartSuffix').existsSync(), isFalse);
      expect(temp.listSync().whereType<File>(), isEmpty);
    });

    test('a failing write deletes the .part', () async {
      final a = write('src/a.bin', [1]);
      // The target's parent is a file, so the archive cannot be created.
      final blocker = write('blocker', [0]);
      final target = p.join(blocker, 'x.ttsmod');

      await expectLater(
        writeZipArchive(
          ZipWriteRequest(
            targetPath: target,
            entries: [(sourcePath: a, entryName: 'a.bin')],
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(File('$target$zipPartSuffix').existsSync(), isFalse);
    });
  });

  group('BackupZipIsolate', () {
    test('reports progress per entry and returns the result', () async {
      final a = write('src/Mods/Images/a.png', List.filled(2048, 7));
      final b = write('src/Mods/Workshop/1.json', [0x7b, 0x7d]);
      final target = p.join(temp.path, 'iso.ttsmod');
      final progress = <ZipProgress>[];

      final result = await BackupZipIsolate.write(
        ZipWriteRequest(
          targetPath: target,
          entries: [
            (sourcePath: a, entryName: 'Mods/Images/a.png'),
            (sourcePath: b, entryName: 'Mods/Workshop/1.json'),
          ],
        ),
        onProgress: progress.add,
      );

      expect(result.written, 2);
      expect(progress.map((p) => (p.done, p.total)), [(1, 2), (2, 2)]);
      expect(progress.last.entryName, 'Mods/Workshop/1.json');
      expect(readBack(target).keys, [
        'Mods/Images/a.png',
        'Mods/Workshop/1.json',
      ]);
    });

    test('a token cancelled up front fails without writing', () async {
      final a = write('src/a.bin', [1]);
      final target = p.join(temp.path, 'never.ttsmod');
      final token = CancellationToken()..cancel('test');

      await expectLater(
        BackupZipIsolate.write(
          ZipWriteRequest(
            targetPath: target,
            entries: [(sourcePath: a, entryName: 'a.bin')],
          ),
          token: token,
        ),
        throwsA(isA<OperationCancelledException>()),
      );
      expect(File(target).existsSync(), isFalse);
      expect(File('$target$zipPartSuffix').existsSync(), isFalse);
    });

    test('a token cancelled mid-run stops and cleans up', () async {
      // Enough sizeable entries that the cancel sent on the first progress
      // message arrives before the loop ends; if the isolate is quicker the
      // run completes, which the assertions below also accept as long as
      // no .part is left behind.
      final sources = [
        for (var i = 0; i < 12; i++)
          write('src/f$i.bin', List.filled(1024 * 1024, i)),
      ];
      final target = p.join(temp.path, 'mid.ttsmod');
      final token = CancellationToken();

      try {
        await BackupZipIsolate.write(
          ZipWriteRequest(
            targetPath: target,
            entries: [
              for (final source in sources)
                (sourcePath: source, entryName: p.basename(source)),
            ],
          ),
          token: token,
          onProgress: (_) => token.cancel('stop'),
        );
        expect(File(target).existsSync(), isTrue);
      } on OperationCancelledException {
        expect(File(target).existsSync(), isFalse);
      }
      expect(File('$target$zipPartSuffix').existsSync(), isFalse);
    });

    test('an isolate failure surfaces as ZipIsolateException', () async {
      final blocker = write('blocker', [0]);
      await expectLater(
        BackupZipIsolate.write(
          ZipWriteRequest(
            targetPath: p.join(blocker, 'x.ttsmod'),
            entries: const [],
          ),
        ),
        throwsA(isA<ZipIsolateException>()),
      );
    });
  });
}
